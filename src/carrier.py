# SPDX-License-Identifier: Apache-2.0
"""A single Office graphic carries both its visible preview and editable source.

Office sanitizes SVG metadata. The source is instead in a standard, uncompressed
PNG iTXt entry inside the SVG's data-URI image, which Office preserves.
"""
import base64
import io
import xml.etree.ElementTree as ET
from pathlib import Path
from PIL import Image, PngImagePlugin
from metadata import decode, encode

KEY = "ChemOffice.Source"
SVG = "http://www.w3.org/2000/svg"
XLINK = "http://www.w3.org/1999/xlink"
MAX_CARRIER_BYTES = 48 * 1024 * 1024


def create_carrier(source: bytes, preview: Path, drawing_id: str, output: Path) -> str:
    tag = encode(source, drawing_id)
    metadata = PngImagePlugin.PngInfo()
    metadata.add_itxt(KEY, tag, zip=False)
    with Image.open(preview) as image:
        image.load()
        if image.width * image.height > 32_000_000:
            raise ValueError("Preview is too large")
        image = image.convert("RGBA")
        data = io.BytesIO()
        image.save(data, format="PNG", pnginfo=metadata)
        width, height = image.size
    payload = base64.b64encode(data.getvalue()).decode("ascii")
    output.write_text(f'<svg xmlns="{SVG}" xmlns:xlink="{XLINK}" width="{width}" '
                      f'height="{height}" viewBox="0 0 {width} {height}">'
                      f'<image width="{width}" height="{height}" '
                      f'xlink:href="data:image/png;base64,{payload}"/></svg>')
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
    return matches[0]
