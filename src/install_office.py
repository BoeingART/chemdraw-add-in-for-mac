#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Install only our two sideload manifests; never change Keychain trust here."""
import argparse
import http.client
import ssl
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def prepare_tls(root=ROOT):
    directory = root/'work/tls'
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    directory.chmod(0o700)
    cert, key = directory/'localhost.pem', directory/'localhost-key.pem'
    if cert.exists() and key.exists(): return cert
    config = directory/'openssl.cnf'
    config.write_text('''[req]
distinguished_name=dn
x509_extensions=ext
prompt=no
[dn]
CN=ChemOffice Localhost
O=ChemOffice for Mac Local Preview
[ext]
subjectAltName=DNS:localhost,IP:127.0.0.1
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
''')
    subprocess.run(['/usr/bin/openssl','req','-x509','-newkey','rsa:2048','-nodes',
                    '-days','365','-keyout',str(key),'-out',str(cert),'-config',str(config)],
                   check=True, capture_output=True)
    key.chmod(0o600)
    cert.chmod(0o644)
    return cert


def destinations(home):
    return [home/'Library/Containers'/bundle/'Data/Documents/wef/chemoffice-for-mac.xml'
            for bundle in ('com.microsoft.Word','com.microsoft.Powerpoint')]


def app_store_apps():
    return [name for name in ('Word','PowerPoint')
            if (Path('/Applications')/f'Microsoft {name}.app/Contents/_MASReceipt/receipt').is_file()]


def check_installation():
    for target in destinations(Path.home()):
        try:
            target.stat()
            print('Manifest present: '+str(target))
        except FileNotFoundError: print('Manifest missing: '+str(target))
        except PermissionError: print('macOS protects this folder; confirm the entry in Office: '+str(target))
    stored = app_store_apps()
    if stored:
        print('Mac App Store build detected: '+', '.join(stored))
        print('Microsoft documents Office.com builds for local add-in development. A listed entry may still be disabled; see docs/installation.md.')
    cert=ROOT/'work/tls/localhost.pem'
    if cert.exists():
        trusted=subprocess.run(['/usr/bin/security','verify-cert','-q','-c',str(cert),'-p','ssl','-s','localhost'],capture_output=True)
        print('Local certificate: '+('trusted for localhost' if trusted.returncode==0 else 'run Trust Local Connection.command'))
        try:
            connection=http.client.HTTPSConnection('localhost',17524,context=ssl.create_default_context(cafile=str(cert)),timeout=3)
            connection.request('GET','/api/status')
            response=connection.getresponse()
            print('Local helper: '+('running' if response.status==200 else 'unavailable'))
            connection.close()
        except OSError: print('Local helper: open Start ChemOffice.command')
    print('Find the entry: Home → Add-ins → Developer Add-ins → ChemOffice for Mac.')
    print('The ChemOffice ribbon tab is available only after Office successfully activates the add-in.')


def install(home=None, root=ROOT):
    cert = prepare_tls(root)
    source = root/'office/addin/manifest.xml'
    staging=root/'work/install'
    staging.mkdir(parents=True,exist_ok=True)
    shutil.copy2(source,staging/'chemoffice-for-mac.xml')
    blocked=[]
    for target in destinations(home or Path.home()):
        try:
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
            print(f'Installed: {target}')
        except PermissionError:
            blocked.append(target)
            print(f'macOS protected: {target.parent}')
    if blocked:
        print('\nUse Finder to create the wef folders above and copy this file into each:')
        print(staging/'chemoffice-for-mac.xml')
        print('Full Finder steps: docs/installation.md. No security setting was changed.')
    print('\n'+('After completing the Finder copy: ' if blocked else 'Next: ')+'trust the local connection once, start ChemOffice, then restart Word and PowerPoint.')
    print('Find the entry under Home → Add-ins → Developer Add-ins → ChemOffice for Mac. The ribbon requires successful activation.')
    result = subprocess.check_output(['/usr/bin/openssl','x509','-in',str(cert),'-noout','-fingerprint','-sha256'],text=True)
    print(result.strip())
    return not blocked


if __name__ == '__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('action',choices=['install','check'])
    args=parser.parse_args()
    if args.action=='install':
        if app_store_apps():
            print('Mac App Store Office detected. A local developer entry may be disabled. See docs/installation.md before continuing.')
        if not install(): raise SystemExit(1)
    else: check_installation()
