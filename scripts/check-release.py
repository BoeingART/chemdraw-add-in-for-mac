#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Check automatic-update assets before a draft becomes a public release."""
import argparse
import hashlib
import json
import re
from pathlib import Path
from urllib.parse import urlparse

REPOSITORY = "BoeingART/chemdraw-add-in-for-mac"

def validate(release, version, directory, draft=False):
    tag = "v" + version
    if release.get("tag_name") != tag or release.get("prerelease") or (release.get("draft") and not draft):
        raise ValueError("Release version or publication state does not match this build")
    download_tag = tag
    if draft and release.get("draft"):
        page = urlparse(release.get("html_url", ""))
        prefix = f"/{REPOSITORY}/releases/tag/"
        temporary = page.path.removeprefix(prefix)
        if page.scheme != "https" or page.netloc != "github.com" or page.query or page.fragment or not page.path.startswith(prefix) or not (temporary == tag or re.fullmatch(r"untagged-[0-9a-f]{20}", temporary)):
            raise ValueError("Unexpected draft release address")
        # GitHub replaces its temporary draft address with the version tag
        # when publishing. Public releases must use the final address below.
        download_tag = temporary
    for extension in ("zip", "dmg"):
        name = f"ChemDraw-Add-in-for-Mac-{version}-universal.{extension}"
        matches = [asset for asset in release.get("assets", []) if asset.get("name") == name]
        if len(matches) != 1:
            raise ValueError(f"Release needs exactly one {name}")
        asset, file = matches[0], Path(directory) / name
        address = urlparse(asset.get("browser_download_url", ""))
        if address.scheme != "https" or address.netloc != "github.com" or address.path != f"/{REPOSITORY}/releases/download/{download_tag}/{name}" or address.query or address.fragment:
            raise ValueError(f"Unexpected release download address: {name}")
        if asset.get("size") != file.stat().st_size or asset.get("digest") != "sha256:" + hashlib.sha256(file.read_bytes()).hexdigest():
            raise ValueError(f"Uploaded release asset differs from the verified local build: {name}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("metadata", type=Path)
    parser.add_argument("version")
    parser.add_argument("directory", type=Path)
    parser.add_argument("--draft", action="store_true")
    args = parser.parse_args()
    validate(json.loads(args.metadata.read_text()), args.version, args.directory, args.draft)
    print("PASS release includes the verified automatic-update ZIP and first-install DMG")
