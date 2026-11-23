#!/bin/bash
# Instala (o quita) el LaunchAgent que arranca WhisperFlow al iniciar sesión.
#
#   ./scripts/install-login-item.sh              # usa build/WhisperFlow.app
#   ./scripts/install-login-item.sh /Applications/WhisperFlow.app
#   ./scripts/install-login-item.sh --remove
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LABEL="com.local.whisperflow"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

remove_agent() {
    launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
    rm -f "$PLIST"
    echo "LaunchAgent eliminado. WhisperFlow ya no arrancará solo."
}

if [[ "${1:-}" == "--remove" ]]; then
    remove_agent
    exit 0
fi

APP="${1:-$ROOT/build/WhisperFlow.app}"

if [[ ! -d "$APP" ]]; then
    echo "No existe la app en: $APP"
    echo "Compilá primero con ./build.sh"
    exit 1
fi

mkdir -p "$HOME/Library/LaunchAgents"

# `open` (y no el binario directo): ejecutar Contents/MacOS/WhisperFlow a mano
# deja el proceso vivo pero sin inicializar NSApplication.
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/open</string>
        <string>-g</string>
        <string>-a</string>
        <string>$APP</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>LimitLoadToSessionType</key>
    <string>Aqua</string>
    <key>ProcessType</key>
    <string>Interactive</string>
</dict>
</plist>
EOF

plutil -lint "$PLIST" >/dev/null

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"

echo "Instalado: $PLIST"
echo "Arranca solo desde: $APP"
echo "Para desinstalarlo: ./scripts/install-login-item.sh --remove"
