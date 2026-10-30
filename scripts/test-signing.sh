#!/bin/zsh
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
CFM_PROJECT="${0:A:h:h}"
source "$CFM_PROJECT/scripts/signing.sh"
cfm_resolve_application_signing
CFM_TEMP="$(mktemp -d)"
trap 'rm -rf "$CFM_TEMP"' EXIT
for CFM_REVISION in 1 2; do
    print -r -- "print(\"signing regression $CFM_REVISION\")" > "$CFM_TEMP/main.swift"
    xcrun swiftc "$CFM_TEMP/main.swift" -o "$CFM_TEMP/version-$CFM_REVISION"
    /usr/bin/codesign --force --sign "$CFM_APP_SIGNING_ID" --timestamp --options runtime --identifier com.chemdraw_addin.mac.signing-test "$CFM_TEMP/version-$CFM_REVISION"
    cfm_verify_developer_id_code "$CFM_TEMP/version-$CFM_REVISION"
done
CFM_REQUIREMENT="$(/usr/bin/codesign -d -r- "$CFM_TEMP/version-1" 2>&1 | /usr/bin/sed -n 's/^designated => //p')"
[[ "$CFM_REQUIREMENT" == *'anchor apple generic'* && "$CFM_REQUIREMENT" == *"$CFM_TEAM_ID"* ]]
for CFM_REVISION in 1 2; do
    /usr/bin/codesign --verify --strict -R "=$CFM_REQUIREMENT" "$CFM_TEMP/version-$CFM_REVISION"
done
print 'PASS Developer ID revisions share a stable team identity, Hardened Runtime and secure timestamps'
/bin/cp "$CFM_TEMP/version-2" "$CFM_TEMP/ad-hoc"
/usr/bin/codesign --force --sign - --identifier com.chemdraw_addin.mac.signing-test "$CFM_TEMP/ad-hoc" 2>/dev/null
if /usr/bin/codesign --verify --strict -R "=$CFM_REQUIREMENT" "$CFM_TEMP/ad-hoc" 2>/dev/null; then
    print 'FAIL an unrelated signature impersonated the fixed identity'; exit 1
fi
print 'PASS matching a bundle name without the project signing key cannot reuse its identity'
