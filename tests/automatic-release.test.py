# SPDX-License-Identifier: Apache-2.0
"""Exercise release gating locally. Command shims never publish to GitHub."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

PROJECT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("check_release", PROJECT / "scripts/check-release.py")
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)

class AutomaticReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for name in ("scripts", "packaging", "dist", "bin"):
            (self.root / name).mkdir()
        self.version = "1.5.1"
        (self.root / "VERSION").write_text(self.version)
        (self.root / "packaging/ReleaseNotes.md").write_text("Updated artwork and automatic application updates.\n")
        for name in ("release.sh", "check-release.py"):
            shutil.copy(PROJECT / "scripts" / name, self.root / "scripts" / name)
        assets = []
        for extension in ("zip", "dmg"):
            name = f"ChemDraw-Add-in-for-Mac-{self.version}-universal.{extension}"
            data = ("signed " + extension).encode()
            (self.root / "dist" / name).write_bytes(data)
            assets.append(dict(name=name, size=len(data), digest="sha256:" + hashlib.sha256(data).hexdigest(), browser_download_url=f"https://github.com/{checker.REPOSITORY}/releases/download/v{self.version}/{name}"))
        self.release = dict(tag_name="v" + self.version, draft=True, prerelease=False, assets=assets)
        self.metadata = self.root / "metadata.json"
        self.log = self.root / "calls.jsonl"
        self.write_metadata()
        shim = self.root / "bin/shim"
        shim.write_text(f"#!{sys.executable}\n" + r'''
import json, os, pathlib, subprocess, sys
name, args = pathlib.Path(sys.argv[0]).name, sys.argv[1:]
with open(os.environ['TEST_CALLS'], 'a') as out: out.write(json.dumps([name] + args) + '\n')
if name == 'git':
    if args[:2] == ['status', '--porcelain']: print(' M changed' if os.environ.get('TEST_DIRTY') else '', end='')
    else: print('test-release-commit')
elif name == 'gh':
    if args[:2] == ['release', 'view']:
        if os.environ.get('TEST_PUBLISHED'): print('false')
        else: sys.exit(1)
    elif args[0] == 'api': print(pathlib.Path(os.environ['TEST_METADATA']).read_text())
    elif args[:2] == ['release', 'edit']:
        p = pathlib.Path(os.environ['TEST_METADATA']); data = json.loads(p.read_text()); data['draft'] = False; p.write_text(json.dumps(data))
elif name == 'python3': sys.exit(subprocess.run([os.environ['TEST_PYTHON']] + args).returncode)
''')
        shim.chmod(0o755)
        for name in ("git", "gh", "zsh", "python3"):
            (self.root / "bin" / name).symlink_to(shim)
        self.env = dict(os.environ, PATH=str(self.root / "bin") + os.pathsep + os.environ["PATH"], TEST_CALLS=str(self.log), TEST_METADATA=str(self.metadata), TEST_PYTHON=sys.executable)

    def write_metadata(self):
        self.metadata.write_text(json.dumps(self.release))

    def run_release(self, mode):
        self.write_metadata()
        return subprocess.run(["/bin/zsh", str(self.root / "scripts/release.sh"), mode], cwd=self.root, env=self.env, capture_output=True, text=True)

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []

    def test_local_preparation_never_contacts_or_publishes_to_github(self):
        self.assertEqual(self.run_release("--prepare").returncode, 0)
        self.assertFalse(any(call[0] == "gh" for call in self.calls()))

    def test_publish_checks_completed_zip_and_dmg_uploads_before_visibility(self):
        result = self.run_release("--publish")
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.calls()
        create = next(call for call in calls if call[:3] == ["gh", "release", "create"])
        self.assertIn("--draft", create)
        self.assertIn("--verify-tag", create)
        self.assertTrue(any(arg.endswith(".zip") for arg in create))
        self.assertTrue(any(arg.endswith(".dmg") for arg in create))
        verification = next(i for i, call in enumerate(calls) if call[0] == "python3")
        publication = next(i for i, call in enumerate(calls) if call[:3] == ["gh", "release", "edit"])
        self.assertLess(verification, publication)
        self.assertFalse(json.loads(self.metadata.read_text())["draft"])

    def test_missing_automatic_update_archive_keeps_the_release_unpublished(self):
        self.release["assets"] = self.release["assets"][1:]
        self.assertNotEqual(self.run_release("--publish").returncode, 0)
        self.assertFalse(any(call[:3] == ["gh", "release", "edit"] for call in self.calls()))

    def test_wrong_remote_bytes_keep_the_release_unpublished(self):
        self.release["assets"][0]["size"] += 1
        self.assertNotEqual(self.run_release("--publish").returncode, 0)
        self.assertFalse(any(call[:3] == ["gh", "release", "edit"] for call in self.calls()))

    def test_published_versions_are_never_overwritten(self):
        self.env["TEST_PUBLISHED"] = "1"
        self.assertNotEqual(self.run_release("--publish").returncode, 0)
        self.assertFalse(any(call[:3] in (["gh", "release", "upload"], ["gh", "release", "edit"], ["gh", "release", "create"]) for call in self.calls()))

    def test_uncommitted_work_stops_before_building_or_publishing(self):
        self.env["TEST_DIRTY"] = "1"
        self.assertNotEqual(self.run_release("--publish").returncode, 0)
        self.assertFalse(any(call[0] in ("gh", "zsh") for call in self.calls()))

    def test_redirected_duplicate_and_prerelease_assets_are_refused(self):
        for mutation in ("url", "duplicate", "prerelease", "tag"):
            data = json.loads(json.dumps(self.release))
            if mutation == "url": data["assets"][0]["browser_download_url"] += "?redirect=1"
            elif mutation == "duplicate": data["assets"].append(data["assets"][0])
            elif mutation == "prerelease": data["prerelease"] = True
            else: data["tag_name"] = "v1.0.0"
            with self.assertRaises(ValueError): checker.validate(data, self.version, self.root / "dist", draft=True)

if __name__ == "__main__":
    unittest.main(verbosity=2)
