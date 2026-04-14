# ZetSSH App Icon + Notarização + Distribuição Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preparar o ZetSSH para distribuição pública: ícone profissional, Info.plist completo, Sparkle para atualizações automáticas, scripts de notarização e criação de DMG.

**Architecture:** App icon gerado via script a partir de um SVG base. Sparkle SPM integrado ao app. Scripts shell para archive → notarize → staple → DMG. Sem App Store (distribuição direta).

**Tech Stack:** AppKit, Sparkle 2.x (SPM), `xcrun altool`, `create-dmg` (brew), macOS 13+

**Pré-requisito:** Todos os subsistemas A–G concluídos. Apple Developer ID Certificate instalado.

---

## Arquivos

| Ação | Arquivo |
|---|---|
| Create | `zetssh/Assets.xcassets/AppIcon.appiconset/Contents.json` |
| Create | `zetssh/Assets.xcassets/AppIcon.appiconset/icon_*.png` (gerados via script) |
| Create | `scripts/generate-icon.sh` |
| Create | `scripts/notarize.sh` |
| Create | `scripts/create-dmg.sh` |
| Create | `zetssh/App/Info.plist` |
| Modify | `zetssh/App/zetsshApp.swift` — inicializar Sparkle |
| Modify | `zetssh.xcodeproj/project.pbxproj` — adicionar Sparkle SPM |

---

### Task 1: Gerar App Icon

**Files:**
- Create: `scripts/generate-icon.sh`
- Create: `zetssh/Assets.xcassets/AppIcon.appiconset/Contents.json`

- [ ] **Step 1: Criar script de geração do ícone**

```bash
#!/usr/bin/env bash
# scripts/generate-icon.sh
# Gera ícones para todos os tamanhos a partir de um SVG usando rsvg-convert ou sips
# Pré-requisito: brew install librsvg

set -euo pipefail

ICON_DIR="zetssh/Assets.xcassets/AppIcon.appiconset"
mkdir -p "$ICON_DIR"

# Ícone base em SVG — terminal SSH minimalista
cat > /tmp/zetssh-icon.svg << 'EOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">
  <rect width="1024" height="1024" rx="220" fill="#0D1117"/>
  <rect x="80" y="80" width="864" height="864" rx="160" fill="#1C2333"/>
  <!-- Símbolo SSH: prompt de terminal -->
  <text x="512" y="560" font-family="SF Mono, Menlo, monospace" font-size="380"
        fill="#4ADE80" text-anchor="middle" font-weight="700">$_</text>
  <!-- Barra decorativa superior -->
  <rect x="120" y="120" width="784" height="60" rx="30" fill="#21262D"/>
  <circle cx="170" cy="150" r="18" fill="#FF5F57"/>
  <circle cx="230" cy="150" r="18" fill="#FEBC2E"/>
  <circle cx="290" cy="150" r="18" fill="#28C840"/>
</svg>
EOF

# Gerar PNGs para cada tamanho
SIZES=(16 32 64 128 256 512 1024)
for SIZE in "${SIZES[@]}"; do
    rsvg-convert -w "$SIZE" -h "$SIZE" /tmp/zetssh-icon.svg \
        -o "$ICON_DIR/icon_${SIZE}x${SIZE}.png"
    # @2x (exceto 1024)
    if [ "$SIZE" -lt 1024 ]; then
        DOUBLE=$((SIZE * 2))
        rsvg-convert -w "$DOUBLE" -h "$DOUBLE" /tmp/zetssh-icon.svg \
            -o "$ICON_DIR/icon_${SIZE}x${SIZE}@2x.png"
    fi
done

echo "✓ Ícones gerados em $ICON_DIR"
```

- [ ] **Step 2: Executar script (requer librsvg)**

```bash
# Instalar librsvg se necessário
brew install librsvg

cd /Users/zeitune/src/zetssh
chmod +x scripts/generate-icon.sh
./scripts/generate-icon.sh
```

Esperado: arquivos PNG criados em `zetssh/Assets.xcassets/AppIcon.appiconset/`.

- [ ] **Step 3: Criar Contents.json para o AppIcon**

```json
// zetssh/Assets.xcassets/AppIcon.appiconset/Contents.json
{
  "images": [
    {"idiom": "mac", "scale": "1x", "size": "16x16",   "filename": "icon_16x16.png"},
    {"idiom": "mac", "scale": "2x", "size": "16x16",   "filename": "icon_16x16@2x.png"},
    {"idiom": "mac", "scale": "1x", "size": "32x32",   "filename": "icon_32x32.png"},
    {"idiom": "mac", "scale": "2x", "size": "32x32",   "filename": "icon_32x32@2x.png"},
    {"idiom": "mac", "scale": "1x", "size": "64x64",   "filename": "icon_64x64.png"},
    {"idiom": "mac", "scale": "2x", "size": "64x64",   "filename": "icon_64x64@2x.png"},
    {"idiom": "mac", "scale": "1x", "size": "128x128", "filename": "icon_128x128.png"},
    {"idiom": "mac", "scale": "2x", "size": "128x128", "filename": "icon_128x128@2x.png"},
    {"idiom": "mac", "scale": "1x", "size": "256x256", "filename": "icon_256x256.png"},
    {"idiom": "mac", "scale": "2x", "size": "256x256", "filename": "icon_256x256@2x.png"},
    {"idiom": "mac", "scale": "1x", "size": "512x512", "filename": "icon_512x512.png"},
    {"idiom": "mac", "scale": "2x", "size": "512x512", "filename": "icon_1024x1024.png"}
  ],
  "info": {"author": "xcode", "version": 1}
}
```

- [ ] **Step 4: Build para verificar ícone**

```bash
cd /Users/zeitune/src/zetssh
xcodebuild -project zetssh.xcodeproj -scheme zetssh -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"
```

- [ ] **Step 5: Commit**

```bash
cd /Users/zeitune/src/zetssh
git add scripts/generate-icon.sh zetssh/Assets.xcassets/AppIcon.appiconset/
git commit -m "feat: add app icon (terminal-style, all sizes)"
```

---

### Task 2: Info.plist Completo

**Files:**
- Create: `zetssh/App/Info.plist`

- [ ] **Step 1: Criar Info.plist**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
    "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>ZetSSH</string>
    <key>CFBundleDisplayName</key>
    <string>ZetSSH</string>
    <key>CFBundleIdentifier</key>
    <string>com.zetssh.app</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleSignature</key>
    <string>????</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 Matheus Zeitune. All rights reserved.</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>SUFeedURL</key>
    <string>https://github.com/mzet97/zetssh/releases/latest/download/appcast.xml</string>
    <key>SUEnableAutomaticChecks</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
</dict>
</plist>
```

- [ ] **Step 2: Verificar que Xcode usa o Info.plist**

No Xcode: selecionar target `zetssh` → Build Settings → buscar "Info.plist File". Setar para `zetssh/App/Info.plist` se não estiver apontando.

- [ ] **Step 3: Build**

```bash
cd /Users/zeitune/src/zetssh
xcodebuild -project zetssh.xcodeproj -scheme zetssh -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"
```

- [ ] **Step 4: Commit**

```bash
cd /Users/zeitune/src/zetssh
git add zetssh/App/Info.plist
git commit -m "chore: add complete Info.plist with version, copyright and Sparkle feed URL"
```

---

### Task 3: Sparkle — Atualizações Automáticas

**Files:**
- Modify: `zetssh.xcodeproj` (via Xcode SPM UI)
- Modify: `zetssh/App/zetsshApp.swift`

- [ ] **Step 1: Adicionar Sparkle via SPM no Xcode**

File → Add Package Dependencies.
URL: `https://github.com/sparkle-project/Sparkle`
Version: Up to Next Major from `2.6.4`
Produto: `Sparkle` → adicionar ao target `zetssh`.

- [ ] **Step 2: Atualizar zetsshApp.swift para inicializar Sparkle**

```swift
// zetssh/App/zetsshApp.swift
import SwiftUI
import Sparkle

@main
struct zetsshApp: App {
    private let updaterController: SPUStandardUpdaterController

    init() {
        _ = AppDatabase.shared
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 800, minHeight: 500)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("Verificar Atualizações...") {
                    updaterController.updater.checkForUpdates()
                }
            }
        }
    }
}
```

- [ ] **Step 3: Build**

```bash
cd /Users/zeitune/src/zetssh
xcodebuild -project zetssh.xcodeproj -scheme zetssh -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"
```

- [ ] **Step 4: Commit**

```bash
cd /Users/zeitune/src/zetssh
git add zetssh.xcodeproj/ zetssh/App/zetsshApp.swift
git commit -m "feat: integrate Sparkle 2.x for automatic updates"
```

---

### Task 4: Script de Notarização

**Files:**
- Create: `scripts/notarize.sh`

- [ ] **Step 1: Criar script**

```bash
#!/usr/bin/env bash
# scripts/notarize.sh
# Uso: APPLE_ID=you@email.com TEAM_ID=ABCDE12345 APP_PASSWORD=xxxx-xxxx ./scripts/notarize.sh

set -euo pipefail

APP_NAME="ZetSSH"
SCHEME="zetssh"
ARCHIVE_PATH="/tmp/${APP_NAME}.xcarchive"
EXPORT_PATH="/tmp/${APP_NAME}-export"
DMG_PATH="/tmp/${APP_NAME}.dmg"

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
```

- [ ] **Step 2: Tornar executável**

```bash
cd /Users/zeitune/src/zetssh
chmod +x scripts/notarize.sh
```

- [ ] **Step 3: Commit**

```bash
cd /Users/zeitune/src/zetssh
git add scripts/notarize.sh
git commit -m "chore: add notarization script for Developer ID distribution"
```

---

### Task 5: Script de DMG

**Files:**
- Create: `scripts/create-dmg.sh`

- [ ] **Step 1: Instalar create-dmg**

```bash
brew install create-dmg
```

- [ ] **Step 2: Criar script**

```bash
#!/usr/bin/env bash
# scripts/create-dmg.sh
# Uso: APP_PATH=/tmp/ZetSSH-export/ZetSSH.app VERSION=1.0.0 ./scripts/create-dmg.sh

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
```

- [ ] **Step 3: Tornar executável e commitar**

```bash
cd /Users/zeitune/src/zetssh
chmod +x scripts/create-dmg.sh
git add scripts/create-dmg.sh
git commit -m "chore: add DMG creation script for distribution"
```

---

### Task 6: Verificação Final de Distribuição

- [ ] **Step 1: Build release limpo**

```bash
cd /Users/zeitune/src/zetssh
xcodebuild -project zetssh.xcodeproj -scheme zetssh \
    -configuration Release \
    -destination 'platform=macOS' build 2>&1 | grep -E "error:|warning:|BUILD" | head -20
```

Esperado: `** BUILD SUCCEEDED **` com zero erros.

- [ ] **Step 2: Verificar entitlements finais**

```bash
cat zetssh/zetssh.entitlements
```

Esperado: apenas `app-sandbox`, `network.client`, `files.user-selected.read-write`, `keychain-access-groups`. Sem `network.server`.

- [ ] **Step 3: Commit final de versão**

```bash
cd /Users/zeitune/src/zetssh
git tag -a v1.0.0 -m "ZetSSH v1.0.0 — Release"
git push origin main --tags
```
