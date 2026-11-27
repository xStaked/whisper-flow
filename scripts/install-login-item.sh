#!/bin/bash
# Installs (or removes) the LaunchAgent that starts WhisperFlow at login.
#
#   ./scripts/install-login-item.sh              # uses build/WhisperFlow.app
#   ./scripts/install-login-item.sh /Applications/WhisperFlow.app
#   ./scripts/install-login-item.sh --remove
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LABEL="com.local.whisperflow"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

remove_agent() {
    launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
    rm -f "$PLIST"
    echo "LaunchAgent removed. WhisperFlow will no longer start on its own."
}

if [[ "${1:-}" == "--remove" ]]; then
    remove_agent
    exit 0
fi

APP="${1:-$ROOT/build/WhisperFlow.app}"

if [[ ! -d "$APP" ]]; then
    echo "No app found at: $APP"
    echo "Build it first with ./build.sh"
    exit 1
fi

mkdir -p "$HOME/Library/LaunchAgents"

# `open` (never the raw binary): running Contents/MacOS/WhisperFlow by hand
# leaves the process alive without initialising NSApplication.
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

echo "Installed: $PLIST"
echo "Starts automatically from: $APP"
echo "To uninstall: ./scripts/install-login-item.sh --remove"
