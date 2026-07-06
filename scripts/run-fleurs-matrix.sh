#!/bin/bash
# Full FLEURS-hr (914) accuracy+RTF benchmark over the model matrix.
# Metal path, Mac mini M4. RAM is measured separately (scripts probe whisper-cli
# directly under /usr/bin/time -l). Run from the repo root.
cd /Users/akujundzic/Studio/Private/WisperLocal || exit 1
PY=benchmark/.venv/bin/python
MAN=benchmark/data/fleurs-hr-full/manifest.json
mkdir -p benchmark/results

run() {
  label="$1"; model="$2"
  echo "===== $label ====="
  "$PY" benchmark/run_bench.py --model "$model" --manifest "$MAN" \
    --out "benchmark/results/${label}-fleurs914.csv" --label "$label-fleurs914" \
    --lang hr --threads 4 --quiet
  echo ""
}

run "turbo-q8_0"    "models/ggml-large-v3-turbo-q8_0.bin"
run "large-v3-q8_0" "models/ggml-large-v3-q8_0.bin"
echo "===== MATRIX DONE ====="
