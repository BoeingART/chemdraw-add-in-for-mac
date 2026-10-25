#!/bin/zsh
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
PROJECT_DIR="${0:A:h}"
cd "$PROJECT_DIR"
CERT_PATH="$PROJECT_DIR/work/tls/localhost.pem"
[[ -f "$CERT_PATH" ]] || { print 'Open Install Office Add-ins.command first.'; exit 1; }
print 'Word and PowerPoint require a trusted HTTPS connection to this Mac.'
print 'This trusts only the ChemOffice localhost certificate for SSL at localhost.'
print 'It does not install a general-purpose certificate authority.'
/usr/bin/openssl x509 -in "$CERT_PATH" -noout -fingerprint -sha256
read -r 'CFM_ANSWER?Type TRUST to continue, or press Return to cancel: '
[[ "$CFM_ANSWER" == TRUST ]] || exit 0
/usr/bin/security add-trusted-cert -r trustRoot -p ssl -s localhost -k "$HOME/Library/Keychains/login.keychain-db" "$CERT_PATH"
print 'Local connection is ready. Restart Word and PowerPoint, then open ChemOffice under Home → Add-ins.'
read -k 1 '?Press any key to close.'
