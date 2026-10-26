#!/bin/zsh
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
PROJECT_DIR="${0:A:h}"
cd "$PROJECT_DIR"
if [[ ! -x build/chemoffice || ! -x build/event-monitor ]]; then
    print 'Please open Setup.command once, then try again.'
    read -k 1
    exit 1
fi
print 'ChemOffice for Mac is listening for managed figures.'
print 'Double-click a figure, edit in ChemDraw, then press Command-W.'
print 'Office entry: Home → Add-ins → Developer Add-ins → ChemOffice for Mac.'
print 'For installation and local preview compatibility, see docs/installation.md.'
print 'Keep this window open. Press Control-C here to stop.'
exec "$PROJECT_DIR/build/chemoffice" run
