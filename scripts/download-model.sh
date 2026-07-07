#!/bin/bash
# Download the RAM-appropriate whisper model into models/ (ADR-003):
#   <= ~12 GB (Air 8 GB tier)  -> large-v3-turbo q8_0 (direct download)
#   >  ~12 GB (Mac mini M4)     -> large-v3 q8_0 (download f16 + quantize) + turbo fallback
# Requires whisper.cpp to be present (run scripts/setup-whisper.sh first).
set -e
cd "$(dirname "$0")/.." || exit 1

if [ ! -d whisper.cpp ]; then
  echo "whisper.cpp missing — run scripts/setup-whisper.sh first." >&2
  exit 1
fi

mkdir -p models
DL="whisper.cpp/models/download-ggml-model.sh"
GIB=$(( $(sysctl -n hw.memsize) / 1073741824 ))
echo "Detected ${GIB} GB RAM."

# Turbo q8_0 works on every tier (and is the fallback the app looks for).
if [ ! -f models/ggml-large-v3-turbo-q8_0.bin ]; then
  echo "Downloading large-v3-turbo q8_0 (~834 MB) ..."
  bash "$DL" large-v3-turbo-q8_0 models
fi

if [ "$GIB" -gt 12 ] && [ ! -f models/ggml-large-v3-q8_0.bin ]; then
  echo "Accuracy tier: fetching + quantizing large-v3 q8_0 ..."
  [ -f models/ggml-large-v3.bin ] || bash "$DL" large-v3 models
  if [ ! -x whisper.cpp/build/bin/whisper-quantize ]; then
    cmake -S whisper.cpp -B whisper.cpp/build -DCMAKE_BUILD_TYPE=Release >/dev/null
    cmake --build whisper.cpp/build -j --target whisper-quantize >/dev/null
  fi
  whisper.cpp/build/bin/whisper-quantize models/ggml-large-v3.bin models/ggml-large-v3-q8_0.bin q8_0
  rm -f models/ggml-large-v3.bin   # keep only the quantized model
fi

echo "Models ready in models/:"
ls -1sh models/*.bin 2>/dev/null || true
