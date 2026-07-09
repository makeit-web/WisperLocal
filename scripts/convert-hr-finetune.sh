#!/bin/bash
# Convert the Croatian fine-tune (GoranS/whisper-large-v3-turbo-hr-parla, Apache-2.0)
# from Hugging Face to a quantized GGML model -> models/ggml-hr-parla-q8_0.bin.
# Needs torch (~2.5 GB) + a few minutes. This documents how the shipped Croatian
# model was produced; end users just download the prebuilt result from the release.
#
# Benchmark (FLEURS-hr, 100 samples, M4): fine-tune WER 8.5% (median 7.1%) vs
# stock turbo q8_0 WER 11.7% — same 834 MB size + same speed. Retains English.
#
# Provenance / supply-chain (QA 2026-07-08): every remote input is pinned to a
# commit, only safetensors weights are fetched (never a pickle .bin — torch
# pickle deserialization is code execution, and this runs on the machine that
# signs releases), and all work happens in fresh mktemp dirs, never reusable
# fixed /tmp paths. pip deps stay unpinned by accepted trade-off: one-time dev
# script whose output is checksummed for end users (see decision log 008).
set -e
cd "$(dirname "$0")/.." || exit 1
[ -d whisper.cpp ] || bash scripts/setup-whisper.sh

# Pinned 2026-07-08 (current HEADs at conversion time).
HF_REVISION="3247238374e3d81f55b1451a105294b306e093bd"       # GoranS/whisper-large-v3-turbo-hr-parla
OPENAI_WHISPER_COMMIT="04f449b8a437f1bbd3dba5c9f826aca972e7709a"  # openai/whisper (mel filters/tokenizer assets)

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
VENV="$WORK/venv"; HF="$WORK/hr-ft"; OUT="$WORK/out"; OAIW="$WORK/openai-whisper"

python3.11 -m venv "$VENV"
"$VENV/bin/pip" install -q torch transformers numpy huggingface_hub
"$VENV/bin/python" -c "
from huggingface_hub import snapshot_download
snapshot_download(
    'GoranS/whisper-large-v3-turbo-hr-parla',
    revision='$HF_REVISION',
    local_dir='$HF',
    allow_patterns=['model.safetensors', '*.json', '*.txt'],  # no pickle, ever
)"

git clone https://github.com/openai/whisper "$OAIW"
git -C "$OAIW" checkout --detach "$OPENAI_WHISPER_COMMIT"

mkdir -p "$OUT"
"$VENV/bin/python" whisper.cpp/models/convert-h5-to-ggml.py "$HF" "$OAIW" "$OUT"

if [ ! -x whisper.cpp/build/bin/whisper-quantize ]; then
  cmake -S whisper.cpp -B whisper.cpp/build -DCMAKE_BUILD_TYPE=Release >/dev/null
  cmake --build whisper.cpp/build -j --target whisper-quantize >/dev/null
fi
mkdir -p models
whisper.cpp/build/bin/whisper-quantize "$OUT/ggml-model.bin" models/ggml-hr-parla-q8_0.bin q8_0
echo "Done: models/ggml-hr-parla-q8_0.bin"
