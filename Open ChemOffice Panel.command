#!/bin/zsh
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
PROJECT_DIR="${0:A:h}"
if [[ ! -f "$PROJECT_DIR/work/tls/localhost.pem" ]] || ! /usr/bin/curl --silent --fail --max-time 3 --cacert "$PROJECT_DIR/work/tls/localhost.pem" https://localhost:17524/api/status >/dev/null; then
    print 'Open Start ChemOffice.command first. For first-time setup, see docs/installation.md.'
    read -k 1 '?Press any key to close.'
    exit 1
fi
/usr/bin/open https://localhost:17524/taskpane.html
