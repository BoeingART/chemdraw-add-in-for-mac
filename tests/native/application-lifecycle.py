# SPDX-License-Identifier: Apache-2.0
"""Actual AppKit shutdown and signed updates in disposable application bundles."""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import signal
import subprocess
import sys
import tempfile
import time

binary = Path(sys.argv[1]).resolve()
signed = len(sys.argv) == 4
archive = Path(sys.argv[2]).resolve() if signed else None
target = Path(sys.argv[3]).resolve() if signed else None
identity = os.environ.get('CFM_TEST_SIGN_IDENTITY', '-')
project = Path(__file__).resolve().parents[2]

def run(*args):
    return subprocess.run(args, check=True, capture_output=True, text=True).stdout

scenarios = ['quit', 'no-helper', 'timeout', 'launch-failure']
if signed:
    scenarios += ['update', 'retry']
for scenario in scenarios:
    with tempfile.TemporaryDirectory(prefix='chemdraw-lifecycle-') as temporary:
        root = Path(temporary)
        app = root / 'Installed.app'
        macos = app / 'Contents/MacOS'
        resources = app / 'Contents/Resources'
        macos.mkdir(parents=True)
        (resources / 'build').mkdir(parents=True)
        work = root / 'work'
        work.mkdir()
        (work / 'recovery').mkdir()
        draft = work / 'recovery/retained.cdx'
        draft.write_bytes(b'retained editing draft')
        info = plistlib.loads((project / 'packaging/Info.plist').read_bytes())
        info.update(CFBundleExecutable='LifecycleTest', CFBundleShortVersionString='1.5.2', CFBundleVersion='22')
        (app / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
        executable = macos / 'LifecycleTest'
        shutil.copy2(binary, executable)
        helper = resources / 'build/chemoffice'
        shutil.copy2(binary, helper)
        options = ['--timestamp', '--options', 'runtime'] if signed else ['--timestamp=none']
        run('/usr/bin/codesign', '--force', '--sign', identity, *options, '--identifier', 'com.chemdraw_addin.mac.helper', str(helper))
        run('/usr/bin/codesign', '--force', '--sign', identity, *options, str(app))
        args = [str(executable), scenario, str(work)]
        download = None
        if scenario in ['update', 'retry']:
            download = work / 'updates/download' / archive.name
            download.parent.mkdir(parents=True)
            shutil.copy2(archive, download)
            version = plistlib.loads((target / 'Contents/Info.plist').read_bytes())['CFBundleShortVersionString']
            repo = 'BoeingART/chemdraw-add-in-for-mac'
            metadata = root / 'release.json'
            metadata.write_text(json.dumps(dict(tag_name='v'+version, html_url=f'https://github.com/{repo}/releases/tag/v{version}', draft=False, prerelease=False, assets=[dict(name=archive.name, browser_download_url=f'https://github.com/{repo}/releases/download/v{version}/{archive.name}', size=archive.stat().st_size, digest='sha256:'+hashlib.sha256(archive.read_bytes()).hexdigest())])))
            args += [str(metadata), str(download)]
        log = root / 'lifecycle.log'
        try:
            with log.open('w') as output:
                child = subprocess.Popen(args, stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
                child.wait(timeout=40)
                assert child.returncode == 0, log.read_text()
                assert 'PASS actual NSApplication termination completes after helper exit' in log.read_text(), log.read_text()
                if signed and download:
                    deadline = time.monotonic()+40
                    while time.monotonic() < deadline:
                        result = work / 'update-result.json'
                        if result.exists():
                            report = json.loads(result.read_text())
                            assert 'error' not in report, report
                        current = plistlib.loads((app / 'Contents/Info.plist').read_bytes()) if app.exists() else {}
                        if current.get('CFBundleShortVersionString') == version and not download.exists() and not list((work / 'updates').glob('prepared-*')):
                            break
                        time.sleep(0.1)
                    else:
                        raise AssertionError('Signed update did not complete: '+log.read_text())
                    run('/usr/bin/codesign', '--verify', '--deep', '--strict', str(app))
                    if os.environ.get('CFM_REQUIRE_NOTARIZATION') == '1':
                        run('/usr/bin/xcrun', 'stapler', 'validate', str(app))
                        run('/usr/sbin/spctl', '--assess', '--type', 'execute', str(app))
                    assert draft.read_bytes() == b'retained editing draft'
                    print(f'PASS signed {scenario}: production GUI quit, helper exit, replacement, real GUI relaunch, retained draft and staging cleanup', flush=True)
                else:
                    print(f'PASS actual AppKit lifecycle: {scenario}', flush=True)
        finally:
            if log.exists():
                print(log.read_text(), end='', flush=True)
            try:
                os.killpg(child.pid, signal.SIGKILL)
            except (ProcessLookupError, NameError):
                pass
print(f'Passed {len(scenarios)} actual application lifecycle scenarios', flush=True)
