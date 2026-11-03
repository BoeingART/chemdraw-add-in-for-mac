# SPDX-License-Identifier: Apache-2.0
"""Integration checks for the isolated, persistent AppleScript transport."""
import json
import pathlib
import struct
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


class WorkerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.worker = subprocess.Popen(
            [str(ROOT / "build/chemoffice"), "script-worker"],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )

    def tearDown(self):
        self.worker.stdin.close()
        try:
            self.worker.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.worker.kill()
            self.worker.wait()
        self.worker.stdout.close()
        self.worker.stderr.close()
        self.temp.cleanup()

    def script(self, name, body):
        path = pathlib.Path(self.temp.name) / (name + ".scpt")
        subprocess.run(["/usr/bin/osacompile", "-o", str(path), "-e", body], check=True)
        return path

    def request(self, path, arguments=()):
        payload = json.dumps({"path": str(path), "arguments": list(arguments)}).encode()
        self.worker.stdin.write(struct.pack(">I", len(payload)) + payload)
        self.worker.stdin.flush()
        header = self.worker.stdout.read(4)
        self.assertEqual(len(header), 4)
        data = self.worker.stdout.read(struct.unpack(">I", header)[0])
        return json.loads(data)

    def test_arguments_unicode_and_lists_match_osascript(self):
        script = self.script("lists", 'on run argv\nreturn {item 1 of argv, {true, false, 123}, "hello"}\nend run')
        args = ['中文 "quotes" \\ path\nsecond line']
        reference = subprocess.check_output(["/usr/bin/osascript", str(script), *args], text=True).rstrip("\n")
        for _ in range(3):
            self.assertEqual(self.request(script, args), {"result": reference})

    def test_errors_leave_the_protocol_usable(self):
        bad = self.script("error", 'on run argv\nerror "expected failure" number -1234\nend run')
        result = self.request(bad)
        self.assertIn("expected failure", result["error"])
        self.assertIn("-1234", result["error"])
        good = self.script("ok", 'on run argv\nreturn "recovered"\nend run')
        self.assertEqual(self.request(good), {"result": "recovered"})
        self.assertIn("error", self.request(pathlib.Path(self.temp.name) / "missing.scpt"))
        self.assertEqual(self.request(good), {"result": "recovered"})

    def test_cached_script_retains_state_between_requests(self):
        path = self.script("state", 'property hits : 0\non run argv\nset hits to hits + 1\nreturn hits\nend run')
        self.assertEqual(self.request(path), {"result": "1"})
        self.assertEqual(self.request(path), {"result": "2"})


if __name__ == "__main__":
    unittest.main()
