#!/bin/bash
# Faz o Jarvis nativo subir sozinho no login e ficar rodando em segundo plano.
# Só funciona depois que ouvido/build.sh gerar o build/Jarvis.app.
set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$RAIZ/build/Jarvis.app/Contents/MacOS/jarvis-ouvido"
ROTULO="com.ericgarcia.jarvis"
PLIST="$HOME/Library/LaunchAgents/$ROTULO.plist"
LOG="$HOME/Library/Logs/jarvis.log"

if [ ! -x "$APP" ]; then
    echo "erro: $APP não existe. Rode antes:  bash ouvido/build.sh" >&2
    exit 1
fi

mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>              <string>$ROTULO</string>
    <key>ProgramArguments</key>   <array><string>$APP</string></array>
    <key>RunAtLoad</key>          <true/>
    <key>KeepAlive</key>          <true/>
    <key>StandardOutPath</key>    <string>$LOG</string>
    <key>StandardErrorPath</key>  <string>$LOG</string>
</dict>
</plist>
PLIST

launchctl bootout "gui/$(id -u)/$ROTULO" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"

echo "✅ Jarvis instalado — sobe sozinho no login."
echo "   log:      $LOG"
echo "   desligar: launchctl bootout gui/$(id -u)/$ROTULO && rm $PLIST"
