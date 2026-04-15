#!/usr/bin/env bash
# scripts/notarize.sh
# Uso: APPLE_ID=you@email.com TEAM_ID=ABCDE12345 APP_PASSWORD=xxxx-xxxx ./scripts/notarize.sh

set -euo pipefail

APP_NAME="ZetSSH"
SCHEME="zetssh"
ARCHIVE_PATH="/tmp/${APP_NAME}.xcarchive"
EXPORT_PATH="/tmp/${APP_NAME}-export"

echo "→ Archive..."
xcodebuild archive \
    -project zetssh.xcodeproj \
    -scheme "$SCHEME" \
    -archivePath "$ARCHIVE_PATH" \
    -destination "generic/platform=macOS" \
    CODE_SIGN_IDENTITY="Developer ID Application" \
    DEVELOPMENT_TEAM="$TEAM_ID"

echo "→ Export..."
cat > /tmp/export-options.plist << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>method</key><string>developer-id</string>
    <key>teamID</key><string>${TEAM_ID}</string>
    <key>signingStyle</key><string>automatic</string>
</dict></plist>
EOF

xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist /tmp/export-options.plist

APP_PATH="$EXPORT_PATH/${APP_NAME}.app"

echo "→ Notarize (submit)..."
xcrun notarytool submit "$APP_PATH" \
    --apple-id "$APPLE_ID" \
    --team-id "$TEAM_ID" \
    --password "$APP_PASSWORD" \
    --wait

echo "→ Staple..."
xcrun stapler staple "$APP_PATH"

echo "✓ Notarização concluída: $APP_PATH"
