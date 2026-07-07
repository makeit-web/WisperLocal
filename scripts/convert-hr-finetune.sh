#!/bin/bash
# Convert the Croatian fine-tune (GoranS/whisper-large-v3-turbo-hr-parla, Apache-2.0)
# from Hugging Face to a quantized GGML model -> models/ggml-hr-parla-q8_0.bin.
# Needs torch (~2.5 GB) + a few minutes. This documents how the shipped Croatian
# model was produced; end users just download the prebuilt result from the release.
#
# Benchmark (FLEURS-hr, 100 samples, M4): fine-tune WER 8.5% (median 7.1%) vs
# stock turbo q8_0 WER 11.7% — same 834 MB size + same speed. Retains English.
set -e
cd "$(dirname "$0")/.." || exit 1
[ -d whisper.cpp ] || bash scripts/setup-whisper.sh

VENV=/tmp/wl-convert-venv
python3.11 -m venv "$VENV"
"$VENV/bin/pip" install -q torch transformers numpy huggingface_hub

HF=/tmp/hr-ft; OUT=/tmp/hr-ft-out
"$VENV/bin/python" -c "from huggingface_hub import snapshot_download; snapshot_download('GoranS/whisper-large-v3-turbo-hr-parla', local_dir='$HF', ignore_patterns=['runs/*','training_args.bin'])"
[ -d /tmp/openai-whisper ] || git clone --depth 1 https://github.com/openai/whisper /tmp/openai-whisper
mkdir -p "$OUT"
"$VENV/bin/python" whisper.cpp/models/convert-h5-to-ggml.py "$HF" /tmp/openai-whisper "$OUT"

if [ ! -x whisper.cpp/build/bin/whisper-quantize ]; then
  cmake -S whisper.cpp -B whisper.cpp/build -DCMAKE_BUILD_TYPE=Release >/dev/null
  cmake --build whisper.cpp/build -j --target whisper-quantize >/dev/null
fi
mkdir -p models
whisper.cpp/build/bin/whisper-quantize "$OUT/ggml-model.bin" models/ggml-hr-parla-q8_0.bin q8_0
echo "Done: models/ggml-hr-parla-q8_0.bin"
