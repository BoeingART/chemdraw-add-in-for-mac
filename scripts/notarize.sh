#!/bin/zsh
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
CFM_PROJECT="${0:A:h:h}"
CFM_VERSION="$(<"$CFM_PROJECT/VERSION")"
CFM_NOTARY_PROFILE="${CFM_NOTARY_PROFILE:-ChemDraw Add-in}"
CFM_DEFAULT_PKG="$CFM_PROJECT/dist/ChemDraw-Add-in-for-Mac-$CFM_VERSION-universal.pkg"
if [[ "${1:-}" == --check-credentials ]]; then
    xcrun notarytool history --keychain-profile "$CFM_NOTARY_PROFILE" --output-format json >/dev/null
    print -r -- "Notarization credentials are ready: $CFM_NOTARY_PROFILE"
    exit 0
fi
(( $# <= 1 )) || { print -u2 'Usage: zsh scripts/notarize.sh [installer.pkg | --check-credentials]'; exit 1; }
CFM_PKG="${1:-$CFM_DEFAULT_PKG}"
CFM_PKG="${CFM_PKG:A}"
[[ -f "$CFM_PKG" && "$CFM_PKG" == *.pkg ]] || { print -u2 'Build the installer first with zsh scripts/package.sh.'; exit 1; }
CFM_SIGNATURE="$(/usr/sbin/pkgutil --check-signature "$CFM_PKG")"
[[ "$CFM_SIGNATURE" == *'Developer ID Installer: '* ]] || { print -u2 'The installer needs a Developer ID Installer signature.'; exit 1; }

cfm_finish_notarization() {
    local cfm_notarized_pkg="${1:-$CFM_PKG}" cfm_current_digest
    xcrun stapler validate "$cfm_notarized_pkg"
    /usr/sbin/spctl --assess --type install --verbose=2 "$cfm_notarized_pkg"
    if [[ "$cfm_notarized_pkg" != "$CFM_PKG" ]]; then
        cfm_current_digest="$(/usr/bin/shasum -a 256 "$CFM_PKG" | /usr/bin/cut -d ' ' -f 1)"
        if [[ "$cfm_current_digest" != "$CFM_INPUT_DIGEST" ]]; then
            print -u2 -- "The installer changed while Apple was processing it. The accepted installer is retained at $cfm_notarized_pkg. Re-run this command to submit the newer installer."
            return 1
        fi
        /bin/cp "$cfm_notarized_pkg" "$CFM_PKG"
    fi
    # Stapling changes the distributed file. Refresh integrity metadata last.
    if [[ "$CFM_PKG" == "$CFM_DEFAULT_PKG" ]]; then
        (cd "$CFM_PROJECT/dist"; /usr/bin/shasum -a 256 "${CFM_PKG:t}" > SHA256SUMS.txt)
    fi
    print -r -- "Apple notarization and Gatekeeper validation completed: $CFM_PKG"
}

# Re-running a completed submission requires no new upload.
if xcrun stapler validate "$CFM_PKG" >/dev/null 2>&1; then
    cfm_finish_notarization
    exit 0
fi

CFM_INPUT_DIGEST="$(/usr/bin/shasum -a 256 "$CFM_PKG" | /usr/bin/cut -d ' ' -f 1)"
CFM_RECORD="$CFM_PROJECT/build/notarization/${CFM_PKG:t}/$CFM_INPUT_DIGEST"
mkdir -p "$CFM_RECORD"
CFM_SUBMITTED_PKG="$CFM_RECORD/${CFM_PKG:t}"
if [[ ! -f "$CFM_SUBMITTED_PKG" ]]; then
    /bin/cp "$CFM_PKG" "$CFM_SUBMITTED_PKG"
    [[ "$(/usr/bin/shasum -a 256 "$CFM_SUBMITTED_PKG" | /usr/bin/cut -d ' ' -f 1)" == "$CFM_INPUT_DIGEST" ]] || { print -u2 'The installer changed during preparation. Re-run notarization after packaging finishes.'; rm -f "$CFM_SUBMITTED_PKG"; exit 1; }
fi
if [[ ! -f "$CFM_RECORD/submission.json" ]]; then
    xcrun notarytool submit "$CFM_SUBMITTED_PKG" --keychain-profile "$CFM_NOTARY_PROFILE" --output-format json > "$CFM_RECORD/submission.pending.json"
    /usr/bin/plutil -extract id raw -o /dev/null "$CFM_RECORD/submission.pending.json"
    mv "$CFM_RECORD/submission.pending.json" "$CFM_RECORD/submission.json"
fi
CFM_SUBMISSION_ID="$(/usr/bin/plutil -extract id raw -o - "$CFM_RECORD/submission.json")"
print -r -- "Apple notarization submission: $CFM_SUBMISSION_ID"
# Persist the ID before waiting, so timeouts and interrupted waits can resume.
CFM_WAIT_RESULT=0
xcrun notarytool wait "$CFM_SUBMISSION_ID" --keychain-profile "$CFM_NOTARY_PROFILE" --timeout "${CFM_NOTARY_TIMEOUT:-30m}" --output-format json > "$CFM_RECORD/wait.json" || CFM_WAIT_RESULT=$?
xcrun notarytool info "$CFM_SUBMISSION_ID" --keychain-profile "$CFM_NOTARY_PROFILE" --output-format json > "$CFM_RECORD/status.json"
CFM_STATUS="$(/usr/bin/plutil -extract status raw -o - "$CFM_RECORD/status.json")"
case "$CFM_STATUS" in
    Accepted)
        xcrun notarytool log "$CFM_SUBMISSION_ID" --keychain-profile "$CFM_NOTARY_PROFILE" "$CFM_RECORD/log.json"
        xcrun stapler staple "$CFM_SUBMITTED_PKG"
        cfm_finish_notarization "$CFM_SUBMITTED_PKG"
        ;;
    Invalid|Rejected)
        xcrun notarytool log "$CFM_SUBMISSION_ID" --keychain-profile "$CFM_NOTARY_PROFILE" "$CFM_RECORD/log.json"
        print -u2 -- "Apple notarization returned $CFM_STATUS. Review $CFM_RECORD/log.json, fix the reported issue and rebuild."
        exit 1
        ;;
    *)
        print -u2 -- "Apple notarization status: $CFM_STATUS (wait result: $CFM_WAIT_RESULT). Re-run this command to continue submission $CFM_SUBMISSION_ID."
        exit 1
        ;;
esac
