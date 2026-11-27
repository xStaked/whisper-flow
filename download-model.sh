#!/bin/bash
# Downloads the whisper.cpp model WhisperFlow uses.
# Default: large-v3-turbo (q5_0, ~547 MB) — best accuracy/speed for a laptop.
# Pass a different filename to get another one, e.g. ./download-model.sh ggml-small.bin
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODEL="${1:-ggml-large-v3-turbo-q5_0.bin}"
DEST="$ROOT/models/$MODEL"

mkdir -p "$ROOT/models"

if [[ -f "$DEST" ]]; then
    echo "Already present: $DEST"
    exit 0
fi

echo "Downloading $MODEL (~547 MB for turbo q5_0)..."
curl -L --fail --retry 3 --progress-bar \
    -o "$DEST" \
    "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$MODEL"

echo "Done: $DEST"
