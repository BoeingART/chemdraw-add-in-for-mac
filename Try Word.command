#!/bin/zsh
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
PROJECT_DIR="${0:A:h}"
cd "$PROJECT_DIR"
if [[ ! -x .venv/bin/python ]]; then
    print 'Please open Setup.command once, then try again.'
    exit 1
fi
exec .venv/bin/python "$PROJECT_DIR/src/chemoffice.py" demo word
