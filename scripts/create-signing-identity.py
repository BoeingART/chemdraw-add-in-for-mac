#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Create the project's persistent local signing identity in the login keychain."""
from pathlib import Path
import os
import secrets
import subprocess
import tempfile

PROJECT = Path(__file__).resolve().parents[1]
NAME = 'ChemDraw Add-in for Mac Local Signing'
PUBLIC = PROJECT / 'packaging/local-signing-cert.pem'


def run(args, **kwargs):
    return subprocess.run(args, check=True, capture_output=True, **kwargs)


def main():
    os.umask(0o077)
    keychain = Path.home() / 'Library/Keychains/login.keychain-db'
    existing = subprocess.run(['/usr/bin/security', 'find-certificate', '-c', NAME, '-p', str(keychain)], capture_output=True)
    if existing.returncode == 0:
        if PUBLIC.exists() and PUBLIC.read_bytes() != existing.stdout:
            raise SystemExit('The keychain certificate differs from this project. Restore the original signing identity before packaging.')
        PUBLIC.write_bytes(existing.stdout)
        print('Reusing the existing project signing certificate in the login keychain.')
        return
    if PUBLIC.exists():
        raise SystemExit('This project already has a fixed signing certificate. Restore its private key to the login keychain instead of creating a replacement.')
    with tempfile.TemporaryDirectory(prefix='chemdraw-signing-') as folder:
        folder = Path(folder)
        config, key, cert, identity = [folder / name for name in ('openssl.cnf', 'private.pem', 'certificate.pem', 'identity.p12')]
        config.write_text('''[req]
prompt=no
distinguished_name=subject
x509_extensions=signing
[subject]
CN=ChemDraw Add-in for Mac Local Signing
O=ChemDraw Add-in for Mac
[signing]
basicConstraints=critical,CA:TRUE,pathlen:0
keyUsage=critical,digitalSignature,keyCertSign
extendedKeyUsage=critical,codeSigning
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid:always
''')
        run(['/usr/bin/openssl', 'req', '-x509', '-newkey', 'rsa:3072', '-nodes', '-sha256', '-days', '3650', '-config', str(config), '-keyout', str(key), '-out', str(cert)])
        password = secrets.token_urlsafe(32)
        env = dict(os.environ, CHEMDRAW_IDENTITY_PASSWORD=password)
        run(['/usr/bin/openssl', 'pkcs12', '-export', '-name', NAME, '-inkey', str(key), '-in', str(cert), '-out', str(identity), '-passout', 'env:CHEMDRAW_IDENTITY_PASSWORD'], env=env)
        run(['/usr/bin/security', 'import', str(identity), '-k', str(keychain), '-P', password, '-T', '/usr/bin/codesign'])
        # Only the public certificate is retained in the checkout. Temporary
        # private-key and transfer files disappear when this context exits.
        PUBLIC.write_bytes(cert.read_bytes())
    PUBLIC.chmod(0o644)
    print('Created the project signing identity in the login keychain. The checkout contains only its public certificate.')


if __name__ == '__main__':
    main()
