#!/bin/zsh
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
PROJECT_DIR="${0:A:h}"
cd "$PROJECT_DIR"
if [[ ! -x .venv/bin/python || ! -x build/event-monitor ]]; then
    zsh Setup.command
fi
if ! .venv/bin/python src/install_office.py install; then
    print '\nAutomatic copying was blocked. Use the Finder steps in docs/installation.md.'
    /usr/bin/open "$PROJECT_DIR/work/install"
fi
print '\nNo certificate trust setting was changed. Open Trust Local Connection.command to enable the local panel.'
read -k 1 '?Press any key to close.'
