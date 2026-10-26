#!/bin/zsh
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
PROJECT_DIR="${0:A:h}"
cd "$PROJECT_DIR"
if [[ ! -x build/chemoffice ]]; then
    print 'Open Setup.command, then Install Office Add-ins.command.'
else
    "$PROJECT_DIR/build/chemoffice" check
fi
read -k 1 '?Press any key to close.'
