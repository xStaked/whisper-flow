#!/bin/bash
# Builds WhisperFlow.app into ./build and code-signs it ad-hoc.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="$ROOT/build/WhisperFlow.app"
BIN="$APP/Contents/MacOS/WhisperFlow"
RES="$APP/Contents/Resources"
MODEL="$ROOT/models/ggml-large-v3-turbo-q5_0.bin"
WHISPER_BIN="$ROOT/vendor-whisper/build/bin/whisper-cli"

echo "==> limpiando"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$RES"
mkdir -p "$ROOT/build/tmp" "$ROOT/build/modulecache"

# Keep every compiler scratch file inside the project (works in sandboxes and
# keeps the build reproducible).
export TMPDIR="$ROOT/build/tmp"
MODULE_CACHE="$ROOT/build/modulecache"

echo "==> compilando Swift"
swiftc -O -swift-version 5 \
    -target arm64-apple-macos13.0 \
    -module-cache-path "$MODULE_CACHE" \
    -framework AppKit \
    -framework AVFoundation \
    -framework ApplicationServices \
    -framework CoreGraphics \
    -o "$BIN" \
    "$ROOT/Sources/"*.swift

echo "==> empaquetando"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

if [[ -x "$WHISPER_BIN" ]]; then
    cp "$WHISPER_BIN" "$RES/whisper-cli"
    WHISPER_PATH="$RES/whisper-cli"
else
    echo "    (aviso) no está $WHISPER_BIN — se usará el que haya instalado en el sistema"
    WHISPER_PATH=""
fi

FFMPEG="$(command -v ffmpeg || true)"
if [[ -z "$FFMPEG" && -x /opt/homebrew/bin/ffmpeg ]]; then
    FFMPEG="/opt/homebrew/bin/ffmpeg"
fi

python3 - "$MODEL" "$WHISPER_PATH" "$FFMPEG" "$RES/runtime-defaults.json" <<'PY'
import json, sys, os
model, whisper, ffmpeg, out = sys.argv[1:5]
data = {
    "language": "es",
    "modelPath": model if os.path.exists(model) else "",
    "whisperBinaryPath": whisper,
    "ffmpegPath": ffmpeg or "/opt/homebrew/bin/ffmpeg",
    "maxRecordSeconds": 120,
    "soundsEnabled": True,
    "autoInsert": True,
}
with open(out, "w") as handle:
    json.dump(data, handle, indent=2)
print("    runtime-defaults.json:", data["modelPath"] or "(modelo no encontrado)")
PY

echo "==> firmando"
# Sign with the user's Apple Development certificate when available: an ad-hoc
# signature changes on every build and makes macOS drop the microphone and
# accessibility permissions each time.
SIGN_HASH="$(security find-identity -v -p codesigning 2>/dev/null | awk '/Apple Development/ {print $2; exit}')"
if [[ -n "$SIGN_HASH" ]]; then
    echo "    identidad: $SIGN_HASH"
    codesign --force --deep --sign "$SIGN_HASH" "$APP" || echo "    (aviso) codesign falló, la app queda sin firmar"
else
    echo "    sin certificado Apple Development: firma ad-hoc (los permisos se reinician en cada build)"
    codesign --force --deep --sign - "$APP" || echo "    (aviso) codesign falló"
fi

# Refresh Launch Services so Finder/Spotlight see the new bundle.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" 2>/dev/null || true

echo "==> listo: $APP"
