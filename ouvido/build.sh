#!/bin/bash
# Compila o ouvido do Jarvis e monta o Jarvis.app.
#
# O binário vive dentro de um .app de propósito: no macOS a permissão de
# microfone é concedida a um aplicativo, não a um executável solto. Com o
# bundle, o Jarvis aparece com nome próprio em Privacidade e Segurança.
set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$RAIZ/build/Jarvis.app"
CONFIG_PADRAO="$RAIZ/config/acoes.json"

echo "→ limpando build anterior"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "→ gravando Info.plist"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>                 <string>Jarvis</string>
    <key>CFBundleDisplayName</key>          <string>Jarvis</string>
    <key>CFBundleIdentifier</key>           <string>com.ericgarcia.jarvis</string>
    <key>CFBundleExecutable</key>           <string>jarvis-ouvido</string>
    <key>CFBundlePackageType</key>          <string>APPL</string>
    <key>CFBundleShortVersionString</key>   <string>1.0</string>
    <key>CFBundleVersion</key>              <string>1</string>
    <key>LSMinimumSystemVersion</key>       <string>13.0</string>
    <key>LSUIElement</key>                  <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>O Jarvis escuta o microfone para reconhecer palmas e disparar as ações que você configurou.</string>
    <key>JarvisConfigPadrao</key>           <string>$CONFIG_PADRAO</string>
</dict>
</plist>
PLIST

echo "→ compilando (Swift $(swiftc --version | head -1 | sed 's/.*version \([0-9.]*\).*/\1/'))"
swiftc -O \
    -target arm64-apple-macos13.0 \
    -framework AVFoundation \
    -o "$APP/Contents/MacOS/jarvis-ouvido" \
    "$RAIZ/ouvido/Sources/Config.swift" \
    "$RAIZ/ouvido/Sources/DetectorPalmas.swift" \
    "$RAIZ/ouvido/Sources/Executor.swift" \
    "$RAIZ/ouvido/Sources/main.swift"

echo "→ assinando (ad-hoc)"
codesign --force --sign - --identifier com.ericgarcia.jarvis "$APP"

echo
echo "✅ pronto: $APP"
echo "   config: $CONFIG_PADRAO"
