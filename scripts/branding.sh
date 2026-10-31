#!/bin/zsh
# SPDX-License-Identifier: Apache-2.0
# Inkscape is a build-time renderer only; the installed app uses native images.
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
CFM_INKSCAPE="${CFM_INKSCAPE:-$(command -v inkscape || true)}"
[[ -x "$CFM_INKSCAPE" ]] || { print -u2 'Install Inkscape or set CFM_INKSCAPE to its executable before building.'; exit 1; }
CFM_BRANDING="$PROJECT_DIR/build/branding"
mkdir -p "$CFM_BRANDING/app.iconset"
cfm_render() {
    if [[ ! "$3" -nt "$1" || ! "$3" -nt "$PROJECT_DIR/scripts/branding.sh" ]]; then
        "$CFM_INKSCAPE" "$1" --export-area-page --export-width="$2" --export-filename="$3" >/dev/null
    fi
}
for CFM_SIZE in 16 32 80; do
    cfm_render "$PROJECT_DIR/office/addin/icon.svg" "$CFM_SIZE" "$PROJECT_DIR/office/addin/icon-$CFM_SIZE.png"
done
for CFM_SIZE in 16 32 128 256 512; do
    cfm_render "$PROJECT_DIR/office/addin/icon.svg" "$CFM_SIZE" "$CFM_BRANDING/app.iconset/icon_${CFM_SIZE}x${CFM_SIZE}.png"
    CFM_DOUBLE=$((CFM_SIZE * 2))
    cfm_render "$PROJECT_DIR/office/addin/icon.svg" "$CFM_DOUBLE" "$CFM_BRANDING/app.iconset/icon_${CFM_SIZE}x${CFM_SIZE}@2x.png"
done
/usr/bin/iconutil -c icns "$CFM_BRANDING/app.iconset" -o "$CFM_BRANDING/app.icns"
cfm_render "$PROJECT_DIR/assets/menu-bar-icon.svg" 72 "$CFM_BRANDING/menu-bar-icon.png"
print 'Generated application, Office, banner and menu-bar images from the current SVG artwork.'
