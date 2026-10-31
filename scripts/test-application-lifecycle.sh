#!/bin/zsh
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
CFM_PROJECT="${0:A:h:h}"
cd "$CFM_PROJECT"
mkdir -p build
CFM_LIFECYCLE_BINARY="${CFM_LIFECYCLE_BINARY:-$CFM_PROJECT/build/test-application-lifecycle}"
CFM_SOURCES=()
for CFM_SOURCE in NativeLocalization OfficeHost NativeExcelSelection NativeStrings NativePaths NativeCore ChemDrawDiscovery NativePDFVector NativeAutomation NativeSetup NativeActivity NativeUpdates NativeUpdateDownload NativeAppUpdate NativeInstaller NativeLoginItem NativeMenuIcon NativeApplication; do
    CFM_SOURCES+=("src/$CFM_SOURCE.swift")
done
xcrun swiftc -O $CFM_SOURCES tests/native/ApplicationLifecycleTests.swift -o "$CFM_LIFECYCLE_BINARY" -framework Cocoa -framework Security -framework ServiceManagement
if (( $# )); then
    [[ $# == 2 ]] || { print -u2 'Usage: test-application-lifecycle.sh [update.zip signed-app]'; exit 1; }
    source scripts/signing.sh
    cfm_resolve_application_signing
    export CFM_TEST_SIGN_IDENTITY="$CFM_APP_SIGNING_ID"
fi
python3 tests/native/application-lifecycle.py "$CFM_LIFECYCLE_BINARY" "$@"
