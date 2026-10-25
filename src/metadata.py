# SPDX-License-Identifier: Apache-2.0
"""Portable editable drawings carried inside the Office document."""
import base64
import hashlib
import uuid
import zlib
import xml.etree.ElementTree as ET

MAX_SOURCE_BYTES = 8 * 1024 * 1024


def validate_source(source: bytes) -> None:
    if not source or len(source) > MAX_SOURCE_BYTES:
        raise ValueError("Empty or oversized ChemDraw source")
    if ET.fromstring(source).tag != "CDXML":
        raise ValueError("The saved drawing is not a CDXML document")


def encode(source: bytes, drawing_id: str | None = None) -> str:
    validate_source(source)
    drawing_id = str(uuid.UUID(drawing_id)) if drawing_id else str(uuid.uuid4())
    digest = hashlib.sha256(source).hexdigest()
    payload = base64.b64encode(zlib.compress(source)).decode("ascii")
    return f"CFM1:{drawing_id}:{digest}:{payload}"


def decode(tag: str) -> tuple[str, bytes]:
    magic, drawing_id, digest, payload = tag.split(":", 3)
    if magic != "CFM1":
        raise ValueError("This figure has no ChemOffice source")
    drawing_id = str(uuid.UUID(drawing_id))
    stream = zlib.decompressobj()
    source = stream.decompress(base64.b64decode(payload, validate=True), MAX_SOURCE_BYTES + 1)
    if len(source) > MAX_SOURCE_BYTES or stream.unconsumed_tail or not stream.eof:
        raise ValueError("Invalid or oversized source payload")
    validate_source(source)
    if hashlib.sha256(source).hexdigest() != digest:
        raise ValueError("Drawing source checksum mismatch")
    return drawing_id, source
