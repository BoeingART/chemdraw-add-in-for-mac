#!/bin/zsh
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
PROJECT_DIR="${0:A:h}"
cd "$PROJECT_DIR"
print 'Preparing your local ChemOffice preview…'
zsh scripts/build.sh
print '\nReady. Open Start ChemOffice.command for double-click editing.'
print 'For the optional Office panel, open Install Office Add-ins.command and read docs/installation.md.'
