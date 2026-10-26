#!/bin/zsh
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
PROJECT_DIR="${0:A:h}"
cd "$PROJECT_DIR"
if [[ ! -x build/chemoffice || ! -x build/event-monitor ]]; then
    zsh Setup.command
fi
CFM_INSTALL_STATUS=0
"$PROJECT_DIR/build/chemoffice" install || CFM_INSTALL_STATUS=$?
if [[ "$CFM_INSTALL_STATUS" == 2 ]]; then
    print '\nAutomatic copying was blocked. Use the Finder steps in docs/installation.md.'
    /usr/bin/open "$PROJECT_DIR/work/install"
elif [[ "$CFM_INSTALL_STATUS" != 0 ]]; then
    exit "$CFM_INSTALL_STATUS"
fi
print '\nNo certificate trust setting was changed. Open Trust Local Connection.command to enable the local panel.'
read -k 1 '?Press any key to close.'
