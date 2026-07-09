#!/bin/bash
# Download the RAM-appropriate whisper model into models/ (ADR-003):
#   <= ~12 GB (Air 8 GB tier)  -> large-v3-turbo q8_0 (direct download)
#   >  ~12 GB (Mac mini M4)     -> large-v3 q8_0 (download f16 + quantize) + turbo fallback
# Requires whisper.cpp to be present (run scripts/setup-whisper.sh first).
#
# Every download is SHA256-verified (same integrity boundary install-prebuilt.sh
# declares), and a pre-existing file is re-verified rather than trusted for
# existing — a partial download from an interrupted run must never become
# permanent. Model names + RAM tier are re-encoded in src/WisperCore/ModelStore.swift,
# scripts/make-app.sh and scripts/install-prebuilt.sh — keep all in sync.
set -e
cd "$(dirname "$0")/.." || exit 1

# Pinned SHA256s: computed from a benchmarked local download AND cross-checked
# against Hugging Face's published LFS oids (ggerganov/whisper.cpp) 2026-07-08.
TURBO_SHA256="317eb69c11673c9de1e1f0d459b253999804ec71ac4c23c17ecf5fbe24e259a1"   # ggml-large-v3-turbo-q8_0.bin
LARGE_V3_SHA256="64d182b440b98d5203c4f9bd541544d84c605196c4f7b845dfa11fb23594d1e2" # ggml-large-v3.bin (f16, quantize input)

if [ ! -d whisper.cpp ]; then
  echo "whisper.cpp missing — run scripts/setup-whisper.sh first." >&2
  exit 1
fi

# Returns 0 when <file> exists and matches <sha256>; removes it and returns 1
# otherwise, so the caller falls through to a (re-)download.
verify_or_remove() {
  [ -f "$1" ] || return 1
  local got; got="$(shasum -a 256 "$1" | awk '{print $1}')"
  [ "$got" = "$2" ] && return 0
  echo "!! $1 failed SHA256 verification — removing stale/corrupt file." >&2
  echo "   expected: $2" >&2
  echo "   got:      $got" >&2
  rm -f "$1"
  return 1
}

mkdir -p models
DL="whisper.cpp/models/download-ggml-model.sh"
GIB=$(( $(sysctl -n hw.memsize) / 1073741824 ))
echo "Detected ${GIB} GB RAM."

# Turbo q8_0 works on every tier (and is a fallback the app looks for).
if ! verify_or_remove models/ggml-large-v3-turbo-q8_0.bin "$TURBO_SHA256"; then
  echo "Downloading large-v3-turbo q8_0 (~834 MB) ..."
  bash "$DL" large-v3-turbo-q8_0 models
  verify_or_remove models/ggml-large-v3-turbo-q8_0.bin "$TURBO_SHA256" || {
    echo "!! Fresh download failed verification — refusing to keep it." >&2
    exit 1
  }
fi

if [ "$GIB" -gt 12 ] && [ ! -f models/ggml-large-v3-q8_0.bin ]; then
  echo "Accuracy tier: fetching + quantizing large-v3 q8_0 ..."
  # Verify the f16 INPUT before quantizing (the q8_0 output is produced locally,
  # so its hash depends on the quantizer build and cannot be pinned).
  if ! verify_or_remove models/ggml-large-v3.bin "$LARGE_V3_SHA256"; then
    bash "$DL" large-v3 models
    verify_or_remove models/ggml-large-v3.bin "$LARGE_V3_SHA256" || {
      echo "!! Fresh download failed verification — refusing to quantize it." >&2
      exit 1
    }
  fi
  if [ ! -x whisper.cpp/build/bin/whisper-quantize ]; then
    cmake -S whisper.cpp -B whisper.cpp/build -DCMAKE_BUILD_TYPE=Release >/dev/null
    cmake --build whisper.cpp/build -j --target whisper-quantize >/dev/null
  fi
  whisper.cpp/build/bin/whisper-quantize models/ggml-large-v3.bin models/ggml-large-v3-q8_0.bin q8_0
  rm -f models/ggml-large-v3.bin   # keep only the quantized model
fi

echo "Models ready in models/:"
ls -1sh models/*.bin 2>/dev/null || true
