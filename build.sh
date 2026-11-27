#!/bin/bash
# Builds WhisperFlow.app into ./build and code-signs it ad-hoc.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="$ROOT/build/WhisperFlow.app"
BIN="$APP/Contents/MacOS/WhisperFlow"
RES="$APP/Contents/Resources"
MODEL="$ROOT/models/ggml-large-v3-turbo-q5_0.bin"
WHISPER_BIN="$ROOT/vendor-whisper/build/bin/whisper-cli"

echo "==> cleaning"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$RES"
mkdir -p "$ROOT/build/tmp" "$ROOT/build/modulecache"

# Keep every compiler scratch file inside the project (works in sandboxes and
# keeps the build reproducible).
export TMPDIR="$ROOT/build/tmp"
MODULE_CACHE="$ROOT/build/modulecache"

echo "==> compiling Swift"
swiftc -O -swift-version 5 \
    -target arm64-apple-macos13.0 \
    -module-cache-path "$MODULE_CACHE" \
    -framework AppKit \
    -framework AVFoundation \
    -framework ApplicationServices \
    -framework CoreGraphics \
    -Xlinker -weak_framework -Xlinker FoundationModels \
    -o "$BIN" \
    "$ROOT/Sources/"*.swift

echo "==> packaging"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

if [[ -x "$WHISPER_BIN" ]]; then
    cp "$WHISPER_BIN" "$RES/whisper-cli"
    WHISPER_PATH="$RES/whisper-cli"
else
    echo "    (warning) $WHISPER_BIN is missing — will use the one installed on the system"
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
    "language": "en",
    "modelPath": model if os.path.exists(model) else "",
    "whisperBinaryPath": whisper,
    "ffmpegPath": ffmpeg or "/opt/homebrew/bin/ffmpeg",
    "maxRecordSeconds": 120,
    "soundsEnabled": True,
    "autoInsert": True,
    "postProcess": False,
}
with open(out, "w") as handle:
    json.dump(data, handle, indent=2)
print("    runtime-defaults.json:", data["modelPath"] or "(modelo no encontrado)")
PY

echo "==> signing"
# Sign with the user's Apple Development certificate when available: an ad-hoc
# signature changes on every build and makes macOS drop the microphone and
# accessibility permissions each time.
SIGN_HASH="$(security find-identity -v -p codesigning 2>/dev/null | awk '/Apple Development/ {print $2; exit}')"

sign_ad_hoc() {
    codesign --force --deep --sign - "$APP" 2>/dev/null \
        || echo "    (warning) signing failed; the app still runs"
}

if [[ -z "$SIGN_HASH" ]]; then
    echo "    no Apple Development certificate: ad-hoc signature"
    echo "    (macOS permissions reset on every build)"
    sign_ad_hoc
else
    echo "    identity: $SIGN_HASH"
    # codesign can block forever behind a keychain prompt. Never hang the build.
    if perl -e 'alarm shift; exec @ARGV' 20 \
        codesign --force --deep --sign "$SIGN_HASH" "$APP" 2>/dev/null; then
        echo "    signed"
    else
        echo "    (warning) certificate signing blocked; using ad-hoc"
        echo "    unlock the keychain and rebuild to keep the permissions"
        sign_ad_hoc
    fi
fi

# Refresh Launch Services so Finder/Spotlight see the new bundle.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" 2>/dev/null || true

echo "==> done: $APP"
