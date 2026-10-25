# SPDX-License-Identifier: Apache-2.0
"""Verify the actual saved Office package, including its referenced preview."""
import posixpath
import io
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path
from metadata import decode
from PIL import Image, ImageChops, ImageFilter, ImageStat

NS = {
    "w": "http://schemas.openxmlformats.org/wordprocessingml/2006/main",
    "wp": "http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing",
    "a": "http://schemas.openxmlformats.org/drawingml/2006/main",
    "p": "http://schemas.openxmlformats.org/presentationml/2006/main",
    "r": "http://schemas.openxmlformats.org/officeDocument/2006/relationships",
}


def preview_agreement(saved: bytes, expected: bytes) -> dict:
    """Office can resize/re-encode PNGs; compare ink after its size normalization."""
    def on_white(data):
        image = Image.open(io.BytesIO(data)).convert("RGBA")
        canvas = Image.new("RGBA", image.size, "white")
        canvas.alpha_composite(image)
        return canvas.convert("RGB")
    actual = on_white(saved)
    reference = on_white(expected).resize(actual.size, Image.Resampling.LANCZOS)
    mean_error = sum(ImageStat.Stat(ImageChops.difference(actual, reference)).mean) / 3
    ink_a = actual.convert("L").point(lambda v: 255 if v < 180 else 0)
    ink_b = reference.convert("L").point(lambda v: 255 if v < 180 else 0)
    def ink_sum(image): return sum(i * count for i, count in enumerate(image.histogram()))
    count_a, count_b = ink_sum(ink_a), ink_sum(ink_b)
    if min(count_a, count_b) == 0:
        raise RuntimeError("The saved preview or its reference is blank")
    coverage_a = ink_sum(ImageChops.multiply(ink_a, ink_b.filter(ImageFilter.MaxFilter(5)))) / count_a
    coverage_b = ink_sum(ImageChops.multiply(ink_b, ink_a.filter(ImageFilter.MaxFilter(5)))) / count_b
    if mean_error > 1.5 or min(coverage_a, coverage_b) < 0.995:
        raise RuntimeError("Saved preview does not match the final ChemDraw render after Office normalization")
    return {"mean_pixel_error": mean_error, "ink_coverage": [coverage_a, coverage_b],
            "saved_preview_size": list(actual.size)}


def verify_saved_figure(document: str, host: str, drawing_id: str,
                        expected_source: bytes, expected_image: Path) -> dict:
    with zipfile.ZipFile(document) as archive:
        candidates = []
        parts = ["word/document.xml"] if host == "word" else [
            n for n in archive.namelist() if n.startswith("ppt/slides/slide") and n.endswith(".xml")]
        for part in parts:
            root = ET.fromstring(archive.read(part))
            if host == "word":
                drawings = root.findall(".//w:drawing", NS)
                for drawing in drawings:
                    props = drawing.find(".//wp:docPr", NS)
                    tag = props.get("descr", "") if props is not None else ""
                    if tag.startswith(f"CFM1:{drawing_id}:"):
                        candidates.append((part, drawing, tag))
            else:
                tag = None
                for shape in root.findall(".//p:sp", NS):
                    props = shape.find("p:nvSpPr/p:cNvPr", NS)
                    if props is not None and props.get("name") == f"CFM_DATA_{drawing_id}":
                        tag = "".join(shape.itertext())
                for picture in root.findall(".//p:pic", NS):
                    props = picture.find("p:nvPicPr/p:cNvPr", NS)
                    if props is not None and props.get("name") == f"CFM1_{drawing_id}":
                        candidates.append((part, picture, tag))
        if len(candidates) != 1:
            raise RuntimeError("Saved document has an ambiguous or missing managed figure")
        part, drawing, tag = candidates[0]
        _, source = decode(tag or "")
        if source != expected_source:
            raise RuntimeError("Saved Office source differs from the final ChemDraw source")
        blip = drawing.find(".//a:blip", NS)
        if blip is None:
            raise RuntimeError("Saved figure has no preview relationship")
        rel_id = blip.get("{" + NS["r"] + "}embed")
        directory, filename = posixpath.split(part)
        rels = ET.fromstring(archive.read(f"{directory}/_rels/{filename}.rels"))
        targets = [r.get("Target") for r in rels if r.get("Id") == rel_id and r.get("TargetMode") != "External"]
        if len(targets) != 1:
            raise RuntimeError("Saved preview is missing or externally linked")
        target = posixpath.normpath(posixpath.join(directory, targets[0]))
        agreement = preview_agreement(archive.read(target), expected_image.read_bytes())
        return {"source_bytes": len(source), "preview_part": target, "verified_part": part, **agreement}
