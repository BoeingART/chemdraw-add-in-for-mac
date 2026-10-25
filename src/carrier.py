# SPDX-License-Identifier: Apache-2.0
"""Native vector artwork plus an invisible, transparent source envelope.

The 1x1 PNG is metadata only. Visible bonds and text come from ChemDraw's SVG.
Legacy SVG-wrapped raster figures remain readable for upgrading.
"""
import base64
import io
import math
import xml.etree.ElementTree as ET
from pathlib import Path
from PIL import Image, PngImagePlugin
import resvg_py
from metadata import decode, encode

KEY = "ChemOffice.Source"
SVG = "http://www.w3.org/2000/svg"
XLINK = "http://www.w3.org/1999/xlink"
MAX_CARRIER_BYTES = 48 * 1024 * 1024


def render_svg(svg: bytes) -> bytes:
    return resvg_py.svg_to_bytes(svg_string=svg.decode("utf-8"), width=1024)


def has_vectors(svg: bytes) -> bool:
    root = ET.fromstring(svg)
    return any(element.tag in {f"{{{SVG}}}{name}" for name in
                              ("path", "text", "line", "polyline", "polygon", "rect", "circle", "ellipse")}
               for element in root.iter())


def svg_aspect(svg: bytes) -> float:
    """Use the actual SVG canvas; Office may import a non-square SVG as square."""
    bounds = ET.fromstring(svg).get("viewBox", "").replace(",", " ").split()
    if len(bounds) != 4:
        raise ValueError("Native vector canvas has no usable viewBox")
    _, _, width, height = map(float, bounds)
    if not all(math.isfinite(n) and n > 0 for n in (width, height)):
        raise ValueError("Native vector canvas dimensions must be positive and finite")
    return height / width


def create_carrier(source: bytes, preview: Path, drawing_id: str, output: Path,
                   vector: Path | None = None) -> str:
    vector = vector or preview.with_suffix(".svg")
    if not vector.is_file() or not has_vectors(vector.read_bytes()):
        raise ValueError("A native vector rendering is required; no raster fallback was inserted")
    root = ET.fromstring(vector.read_bytes())
    # A real vector canvas also provides a predictable Office hit area and keeps
    # black chemical artwork readable on dark pages. This is geometry, not pixels.
    bounds = root.get("viewBox", "").replace(",", " ").split()
    canvas = {"x":"0", "y":"0", "width":"100%", "height":"100%", "fill":"white", "id":"ChemOfficeCanvas"}
    if len(bounds) == 4:
        canvas.update(x=bounds[0], y=bounds[1], width=bounds[2], height=bounds[3])
    root.insert(0, ET.Element(f"{{{SVG}}}rect", canvas))
    # Remove the old envelope when copying a portable figure. Keep native artwork.
    for parent in root.iter():
        for element in list(parent):
            if element.tag != f"{{{SVG}}}image": continue
            href = element.get(f"{{{XLINK}}}href", element.get("href", ""))
            if href.startswith("data:image/png;base64,"):
                with Image.open(io.BytesIO(base64.b64decode(href.split(",", 1)[1]))) as image:
                    if image.info.get(KEY): parent.remove(element)
    for element in root.iter():
        if element.tag in {f"{{{SVG}}}script", f"{{{SVG}}}foreignObject"}:
            raise ValueError("Active SVG content is not supported")
        href = element.get(f"{{{XLINK}}}href", element.get("href", ""))
        if href and not href.startswith(("#", "data:image/")):
            raise ValueError("External SVG resources are not supported")
    tag = encode(source, drawing_id)
    metadata = PngImagePlugin.PngInfo()
    metadata.add_itxt(KEY, tag, zip=False)
    data = io.BytesIO()
    Image.new("RGBA", (1, 1), (0, 0, 0, 0)).save(data, format="PNG", pnginfo=metadata)
    payload = base64.b64encode(data.getvalue()).decode("ascii")
    ET.SubElement(root, f"{{{SVG}}}image", {"x": "0", "y": "0", "width": "1", "height": "1",
                                         "opacity": "0", f"{{{XLINK}}}href": f"data:image/png;base64,{payload}"})
    ET.register_namespace("", SVG); ET.register_namespace("xlink", XLINK)
    output.write_bytes(ET.tostring(root))
    return tag


def read_carrier(svg: bytes) -> tuple[str, bytes]:
    if len(svg) > MAX_CARRIER_BYTES:
        raise ValueError("Carrier is too large")
    root = ET.fromstring(svg)
    matches = []
    for element in root.iter(f"{{{SVG}}}image"):
        href = element.get(f"{{{XLINK}}}href", element.get("href", ""))
        if not href.startswith("data:image/png;base64,"):
            continue
        png = base64.b64decode(href.split(",", 1)[1], validate=True)
        with Image.open(io.BytesIO(png)) as image:
            tag = image.info.get(KEY)
            if tag:
                decode(tag)  # Reject corruption before treating it as editable.
                matches.append((tag, png))
    if len(matches) != 1:
        raise ValueError("Expected one ChemOffice source inside the graphic")
    tag, png = matches[0]
    return tag, render_svg(svg) if has_vectors(svg) else png
