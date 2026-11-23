#!/bin/bash
# Deja el proyecto listo desde cero: compila whisper.cpp, baja los modelos y
# empaqueta la app. Es idempotente: lo que ya existe se saltea.
#
#   ./scripts/bootstrap.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

step() { printf "\n\033[1m==> %s\033[0m\n" "$1"; }
skip() { printf "    ya está: %s\n" "$1"; }

# ---------------------------------------------------------------- 1. toolchain
step "Herramientas del sistema"

if ! command -v swiftc >/dev/null 2>&1; then
    echo "ERROR: falta el compilador de Swift."
    echo "       Instalá las Command Line Tools con:  xcode-select --install"
    exit 1
fi
echo "    swiftc: $(swiftc --version 2>&1 | head -1)"

if ! command -v ffmpeg >/dev/null 2>&1; then
    echo "AVISO: falta ffmpeg (necesario para convertir el audio a 16 kHz)."
    echo "       Instalalo con:  brew install ffmpeg"
else
    echo "    ffmpeg: $(command -v ffmpeg)"
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo "ERROR: falta python3 (lo usa build.sh)."
    exit 1
fi

mkdir -p models build/tmp build/modulecache

# ------------------------------------------------------------------- 2. cmake
step "cmake portable"
CMAKE="$ROOT/vendor/cmake/CMake.app/Contents/bin/cmake"
if [[ -x "$CMAKE" ]]; then
    skip "$CMAKE"
else
    mkdir -p vendor
    echo "    descargando cmake 3.31.6 (~75 MB)"
    curl -L --fail --retry 3 -o vendor/cmake.tar.gz \
        https://github.com/Kitware/CMake/releases/download/v3.31.6/cmake-3.31.6-macos-universal.tar.gz
    tar -xzf vendor/cmake.tar.gz -C vendor
    mv vendor/cmake-3.31.6-macos-universal vendor/cmake
    rm -f vendor/cmake.tar.gz
fi

# --------------------------------------------------------------- 3. whisper.cpp
step "whisper.cpp"
if [[ -x "$ROOT/vendor-whisper/build/bin/whisper-cli" ]]; then
    skip "whisper-cli"
else
    if [[ ! -d "$ROOT/vendor-whisper/.git" ]]; then
        echo "    clonando whisper.cpp"
        git clone --depth 1 https://github.com/ggerganov/whisper.cpp vendor-whisper
    fi
    echo "    compilando (CPU + Accelerate, ~2-4 min)"
    # Sin Metal: en muchos Macs no está el compilador de shaders (xcrun metal).
    "$CMAKE" -B vendor-whisper/build -S vendor-whisper \
        -DCMAKE_BUILD_TYPE=Release \
        -DGGML_METAL=OFF -DWHISPER_COREML=OFF \
        -DBUILD_SHARED_LIBS=OFF \
        -DWHISPER_BUILD_TESTS=OFF -DWHISPER_BUILD_SERVER=OFF >/dev/null
    "$CMAKE" --build vendor-whisper/build --config Release -j "$(sysctl -n hw.ncpu)" >/dev/null
fi

# ------------------------------------------------------------------ 4. modelos
step "Modelo de voz (whisper)"
if [[ -f "$ROOT/models/ggml-large-v3-turbo-q5_0.bin" ]]; then
    skip "ggml-large-v3-turbo-q5_0.bin (547 MB)"
else
    "$ROOT/download-model.sh"
fi

# --------------------------------------------------------------- 5. llama.cpp
step "llama.cpp para la limpieza con IA (opcional)"
if [[ -n "$(find "$ROOT/vendor-llama" -name llama-completion -type f 2>/dev/null | head -1)" ]]; then
    skip "llama-completion"
else
    mkdir -p vendor-llama
    TAG="b12589"   # build con binarios macOS arm64 + Metal
    echo "    descargando llama.cpp $TAG (~16 MB)"
    curl -L --fail --retry 3 -o vendor-llama/llama.tar.gz \
        "https://github.com/ggml-org/llama.cpp/releases/download/$TAG/llama-$TAG-bin-macos-arm64.tar.gz"
    tar -xzf vendor-llama/llama.tar.gz -C vendor-llama
    rm -f vendor-llama/llama.tar.gz
fi

step "Modelo de limpieza (Qwen 2.5 3B)"
LLM="$ROOT/models/Qwen2.5-3B-Instruct-Q4_K_M.gguf"
if [[ -f "$LLM" ]]; then
    skip "Qwen2.5-3B-Instruct-Q4_K_M.gguf (1.8 GB)"
else
    echo "    descargando 1.8 GB (solo si vas a usar la limpieza con IA)"
    curl -L --fail --retry 3 -o "$LLM" \
        https://huggingface.co/bartowski/Qwen2.5-3B-Instruct-GGUF/resolve/main/Qwen2.5-3B-Instruct-Q4_K_M.gguf
fi

# ---------------------------------------------------------------- 6. build app
step "Compilando WhisperFlow.app"
"$ROOT/build.sh"

cat <<EOF

Listo. Siguientes pasos:

  open "$ROOT/build/WhisperFlow.app"
  ./scripts/install-login-item.sh     # opcional: arrancar al iniciar sesión

La primera vez macOS va a pedir micrófono y accesibilidad.
EOF
