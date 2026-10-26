#!/bin/zsh
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
PROJECT_DIR="${0:A:h}"
cd "$PROJECT_DIR"
if [[ ! -x build/chemoffice ]]; then
    print 'Please open Setup.command once, then try again.'
    exit 1
fi
exec "$PROJECT_DIR/build/chemoffice" demo word
