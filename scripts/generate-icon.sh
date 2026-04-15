#!/usr/bin/env bash
# scripts/generate-icon.sh
# Gera ícones para todos os tamanhos a partir de um SVG usando rsvg-convert
# Pré-requisito: brew install librsvg

set -euo pipefail

ICON_DIR="zetssh/Assets.xcassets/AppIcon.appiconset"
mkdir -p "$ICON_DIR"

cat > /tmp/zetssh-icon.svg << 'EOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">
  <rect width="1024" height="1024" rx="220" fill="#0D1117"/>
  <rect x="80" y="80" width="864" height="864" rx="160" fill="#1C2333"/>
  <text x="512" y="560" font-family="SF Mono, Menlo, monospace" font-size="380"
        fill="#4ADE80" text-anchor="middle" font-weight="700">$_</text>
  <rect x="120" y="120" width="784" height="60" rx="30" fill="#21262D"/>
  <circle cx="170" cy="150" r="18" fill="#FF5F57"/>
  <circle cx="230" cy="150" r="18" fill="#FEBC2E"/>
  <circle cx="290" cy="150" r="18" fill="#28C840"/>
</svg>
EOF

SIZES=(16 32 64 128 256 512 1024)
for SIZE in "${SIZES[@]}"; do
    rsvg-convert -w "$SIZE" -h "$SIZE" /tmp/zetssh-icon.svg \
        -o "$ICON_DIR/icon_${SIZE}x${SIZE}.png"
    if [ "$SIZE" -lt 1024 ]; then
        DOUBLE=$((SIZE * 2))
        rsvg-convert -w "$DOUBLE" -h "$DOUBLE" /tmp/zetssh-icon.svg \
            -o "$ICON_DIR/icon_${SIZE}x${SIZE}@2x.png"
    fi
done

echo "✓ Ícones gerados em $ICON_DIR"
