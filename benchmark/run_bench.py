"""Benchmark harness: run whisper-cli over a manifest, score CER/WER, report RTF.

Usage:
  python run_bench.py --model models/ggml-large-v3-turbo-q8_0.bin \
      --manifest data/fleurs-hr/manifest.json --out results/turbo-q8_0.csv \
      --label turbo-q8_0-metal [--prompt "..."] [--limit N] [--threads 4]

Pure helpers (rtf, aggregate) are unit-tested; the subprocess call is thin.
"""
import argparse
import csv
import json
import math
import os
import statistics
import subprocess
import sys
import time

import soundfile as sf

from score import score

DEFAULT_BIN = "whisper.cpp/build-metal/bin/whisper-cli"


def audio_duration_seconds(path: str) -> float:
    info = sf.info(path)
    return info.frames / float(info.samplerate)


def rtf(proc_seconds: float, audio_seconds: float) -> float:
    """Real-time factor: processing / audio. <1 means faster than real time."""
    if audio_seconds <= 0:
        return float("nan")
    return proc_seconds / audio_seconds


def aggregate(rows: list) -> dict:
    wers = [r["wer"] for r in rows]
    cers = [r["cer"] for r in rows]
    rtfs = [r["rtf"] for r in rows if not math.isnan(r["rtf"])]
    return {
        "n": len(rows),
        "wer_mean": statistics.mean(wers) if wers else float("nan"),
        "wer_median": statistics.median(wers) if wers else float("nan"),
        "cer_mean": statistics.mean(cers) if cers else float("nan"),
        "rtf_mean": statistics.mean(rtfs) if rtfs else float("nan"),
    }


def run_one(binary, model, audio, lang, threads, prompt):
    cmd = [binary, "-m", model, "-f", audio, "-l", lang, "-t", str(threads), "-np", "-nt"]
    if prompt:
        cmd += ["--prompt", prompt]
    t0 = time.monotonic()
    proc = subprocess.run(cmd, capture_output=True, text=True)
    elapsed = time.monotonic() - t0
    hyp = " ".join(proc.stdout.split()).strip()
    return hyp, elapsed, proc.returncode


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", required=True)
    ap.add_argument("--manifest", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--label", default="run")
    ap.add_argument("--bin", default=DEFAULT_BIN)
    ap.add_argument("--lang", default="hr")
    ap.add_argument("--threads", type=int, default=4)
    ap.add_argument("--prompt", default="")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--quiet", action="store_true", help="suppress per-sample lines")
    args = ap.parse_args()

    with open(args.manifest) as f:
        items = json.load(f)
    if args.limit:
        items = items[: args.limit]

    os.makedirs(os.path.dirname(args.out) or ".", exist_ok=True)
    rows = []
    for i, it in enumerate(items):
        hyp, elapsed, rc = run_one(
            args.bin, args.model, it["audio"], args.lang, args.threads, args.prompt
        )
        if rc != 0:
            print(f"[{i}] WARN rc={rc} for {it['audio']}", file=sys.stderr)
        dur = audio_duration_seconds(it["audio"])
        s = score(it["ref"], hyp)
        row = {
            "audio": os.path.basename(it["audio"]),
            "ref_words": s["ref_words"],
            "wer": round(s["wer"], 4),
            "cer": round(s["cer"], 4),
            "rtf": round(rtf(elapsed, dur), 4),
            "audio_s": round(dur, 2),
            "proc_s": round(elapsed, 2),
            "hyp": hyp,
        }
        rows.append(row)
        if not args.quiet:
            print(f"[{i+1}/{len(items)}] wer={row['wer']:.3f} cer={row['cer']:.3f} rtf={row['rtf']:.2f}")
        elif (i + 1) % 100 == 0:
            print(f"[{i+1}/{len(items)}] running...", flush=True)

    with open(args.out, "w", newline="") as f:
        w = csv.DictWriter(
            f, fieldnames=["audio", "ref_words", "wer", "cer", "rtf", "audio_s", "proc_s", "hyp"]
        )
        w.writeheader()
        w.writerows(rows)

    agg = aggregate(rows)
    print(f"\n=== SUMMARY [{args.label}] ===")
    print(json.dumps(agg, indent=2))
    print(f"CSV -> {args.out}")


if __name__ == "__main__":
    main()
