#!/bin/zsh
# SPDX-License-Identifier: Apache-2.0
# Shared Developer ID selection. Source this file from packaging/check scripts.
cfm_find_signing_identity() {
    local cfm_policy="$1" cfm_kind="$2" cfm_requested="$3"
    local cfm_output cfm_line
    local cfm_pattern='^[[:space:]]*[0-9]+\)[[:space:]]+([[:xdigit:]]{40})[[:space:]]+"(.+ \(([A-Z0-9]{10})\))"$'
    local -a cfm_ids=() cfm_names=() cfm_teams=()
    cfm_output="$(/usr/bin/security find-identity -v -p "$cfm_policy")" || return 1
    for cfm_line in "${(@f)cfm_output}"; do
        [[ "$cfm_line" =~ "$cfm_pattern" ]] || continue
        [[ "$match[2]" == "$cfm_kind: "* ]] || continue
        [[ -z "${CFM_TEAM_ID:-}" || "$match[3]" == "$CFM_TEAM_ID" ]] || continue
        [[ -z "$cfm_requested" || "$match[1]" == "$cfm_requested" || "$match[2]" == "$cfm_requested" ]] || continue
        cfm_ids+=("$match[1]"); cfm_names+=("$match[2]"); cfm_teams+=("$match[3]")
    done
    if (( ${#cfm_ids} != 1 )); then
        print -u2 -- "Expected one usable $cfm_kind identity; found ${#cfm_ids}. Create it in Xcode > Settings > Accounts > Manage Certificates, or select it with CFM_TEAM_ID and CFM_SIGN_IDENTITY / CFM_INSTALLER_IDENTITY."
        return 1
    fi
    CFM_RESOLVED_ID="$cfm_ids[1]"
    CFM_RESOLVED_NAME="$cfm_names[1]"
    CFM_RESOLVED_TEAM="$cfm_teams[1]"
}

cfm_resolve_application_signing() {
    cfm_find_signing_identity codesigning 'Developer ID Application' "${CFM_SIGN_IDENTITY:-}" || return 1
    CFM_APP_SIGNING_ID="$CFM_RESOLVED_ID"
    CFM_APP_SIGNING_NAME="$CFM_RESOLVED_NAME"
    export CFM_TEAM_ID="$CFM_RESOLVED_TEAM"
}

cfm_resolve_distribution_signing() {
    cfm_resolve_application_signing || return 1
    cfm_find_signing_identity basic 'Developer ID Installer' "${CFM_INSTALLER_IDENTITY:-}" || return 1
    CFM_INSTALLER_SIGNING_NAME="$CFM_RESOLVED_NAME"
}

cfm_verify_developer_id_code() {
    local cfm_binary="$1" cfm_arch cfm_details
    local cfm_requirement="anchor apple generic and certificate leaf[subject.OU] = \"$CFM_TEAM_ID\" and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"
    /usr/bin/codesign --verify --strict --all-architectures -R "=$cfm_requirement" "$cfm_binary" || return 1
    for cfm_arch in $(/usr/bin/lipo -archs "$cfm_binary"); do
        cfm_details="$(/usr/bin/codesign --display --arch "$cfm_arch" --verbose=4 "$cfm_binary" 2>&1)" || return 1
        if [[ "$cfm_details" != *'flags='*'(runtime)'* || "$cfm_details" != *$'\nTimestamp='* ]]; then
            print -u2 -- "Missing Hardened Runtime or secure timestamp: $cfm_binary ($cfm_arch)"
            return 1
        fi
    done
}
