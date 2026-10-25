#!/bin/zsh
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
PROJECT_DIR="${0:A:h}"
cd "$PROJECT_DIR"
print 'Preparing your local ChemOffice preview…'
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements.txt
zsh scripts/build.sh
print '\nReady. Open Start ChemOffice.command, then open either demo launcher.'
