#!/bin/zsh
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
CFM_PROJECT="${0:A:h:h}"
CFM_CERT="${CFM_SIGN_CERT:-$CFM_PROJECT/packaging/local-signing-cert.pem}"
CFM_CERT_ID="$(/usr/bin/openssl x509 -in "$CFM_CERT" -noout -fingerprint -sha1 | /usr/bin/sed 's/.*=//;s/://g')"
CFM_TEMP="$(mktemp -d)"
trap 'rm -rf "$CFM_TEMP"' EXIT
for CFM_REVISION in 1 2; do
    print -r -- "print(\"signing regression $CFM_REVISION\")" > "$CFM_TEMP/main.swift"
    xcrun swiftc "$CFM_TEMP/main.swift" -o "$CFM_TEMP/version-$CFM_REVISION"
    /usr/bin/codesign --force --sign "$CFM_CERT_ID" --timestamp=none --identifier com.chemdraw_addin.mac.signing-test "$CFM_TEMP/version-$CFM_REVISION" 2>/dev/null
done
CFM_REQUIREMENT="$(/usr/bin/codesign -d -r- "$CFM_TEMP/version-1" 2>&1 | /usr/bin/sed -n 's/^designated => //p')"
[[ -n "$CFM_REQUIREMENT" && "$CFM_REQUIREMENT" == *'certificate root'* ]]
for CFM_REVISION in 1 2; do
    /usr/bin/codesign --verify --strict -R "=$CFM_REQUIREMENT" "$CFM_TEMP/version-$CFM_REVISION"
done
print 'PASS different executable revisions satisfy the same certificate-bound application identity'
/bin/cp "$CFM_TEMP/version-2" "$CFM_TEMP/ad-hoc"
/usr/bin/codesign --force --sign - --identifier com.chemdraw_addin.mac.signing-test "$CFM_TEMP/ad-hoc" 2>/dev/null
if /usr/bin/codesign --verify --strict -R "=$CFM_REQUIREMENT" "$CFM_TEMP/ad-hoc" 2>/dev/null; then
    print 'FAIL an unrelated signature impersonated the fixed identity'; exit 1
fi
print 'PASS matching a bundle name without the project signing key cannot reuse its identity'
