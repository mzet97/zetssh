#!/usr/bin/env bash
# scripts/create-dmg.sh
# Uso: APP_PATH=/tmp/ZetSSH-export/ZetSSH.app VERSION=1.0.0 ./scripts/create-dmg.sh
# Pré-requisito: brew install create-dmg

set -euo pipefail

APP_PATH="${APP_PATH:-/tmp/ZetSSH-export/ZetSSH.app}"
VERSION="${VERSION:-1.0.0}"
OUTPUT="ZetSSH-${VERSION}.dmg"

create-dmg \
    --volname "ZetSSH ${VERSION}" \
    --volicon "zetssh/Assets.xcassets/AppIcon.appiconset/icon_512x512.png" \
    --window-pos 200 120 \
    --window-size 600 400 \
    --icon-size 100 \
    --icon "ZetSSH.app" 150 180 \
    --hide-extension "ZetSSH.app" \
    --app-drop-link 450 180 \
    "$OUTPUT" \
    "$APP_PATH"

echo "✓ DMG criado: $OUTPUT"
