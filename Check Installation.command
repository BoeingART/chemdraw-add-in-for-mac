#!/bin/zsh
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
PROJECT_DIR="${0:A:h}"
cd "$PROJECT_DIR"
if [[ ! -x .venv/bin/python ]]; then
    print 'Open Setup.command, then Install Office Add-ins.command.'
else
    .venv/bin/python src/install_office.py check
fi
read -k 1 '?Press any key to close.'
