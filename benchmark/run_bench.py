"""Benchmark harness: run whisper-cli over a manifest, score CER/WER, report RTF.

Usage:
  python run_bench.py --model models/ggml-large-v3-turbo-q8_0.bin \
      --manifest data/fleurs-hr/manifest.json --out results/turbo-q8_0.csv \
      --label turbo-q8_0-metal [--prompt "..."] [--limit N] [--threads 4]

Pure helpers (rtf, aggregate) are unit-tested; the subprocess call is thin.

Failed whisper-cli invocations (rc != 0, or a per-clip timeout) are recorded in
the `rc` CSV column, counted as `failures` in the summary, EXCLUDED from the
wer/cer/rtf means, and make the process exit 1 — a run with harness errors must
never read as a clean accuracy number (ADR-003 gates model choice on WER).

Known metric caveat: each clip spawns a fresh whisper-cli process, so proc_s /
rtf include process startup + model load + Metal init — a constant per-clip
offset that grows with model size. RTFs are comparable within one run, but
biased when comparing models of different sizes across runs.
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
    """Means over SUCCESSFUL rows only; failures are counted, not averaged.

    Rows without an `rc` key (historical CSVs) count as successes.
    """
    ok = [r for r in rows if r.get("rc", 0) == 0]
    wers = [r["wer"] for r in ok]
    cers = [r["cer"] for r in ok]
    rtfs = [r["rtf"] for r in ok if not math.isnan(r["rtf"])]
    return {
        "n": len(rows),
        "n_scored": len(ok),
        "failures": len(rows) - len(ok),
        "wer_mean": statistics.mean(wers) if wers else float("nan"),
        "wer_median": statistics.median(wers) if wers else float("nan"),
        "cer_mean": statistics.mean(cers) if cers else float("nan"),
        "rtf_mean": statistics.mean(rtfs) if rtfs else float("nan"),
    }


def run_one(binary, model, audio, lang, threads, prompt, timeout_s=600):
    cmd = [binary, "-m", model, "-f", audio, "-l", lang, "-t", str(threads), "-np", "-nt"]
    if prompt:
        cmd += ["--prompt", prompt]
    t0 = time.monotonic()
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout_s)
        rc, stdout = proc.returncode, proc.stdout
    except subprocess.TimeoutExpired:
        # One hung clip must not stall a 914-file matrix run forever.
        rc, stdout = -9, ""
    elapsed = time.monotonic() - t0
    hyp = " ".join(stdout.split()).strip()
    return hyp, elapsed, rc


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
            "rc": rc,
            "hyp": hyp,
        }
        rows.append(row)
        if not args.quiet:
            print(f"[{i+1}/{len(items)}] wer={row['wer']:.3f} cer={row['cer']:.3f} rtf={row['rtf']:.2f}")
        elif (i + 1) % 100 == 0:
            print(f"[{i+1}/{len(items)}] running...", flush=True)

    with open(args.out, "w", newline="") as f:
        w = csv.DictWriter(
            f,
            fieldnames=["audio", "ref_words", "wer", "cer", "rtf", "audio_s", "proc_s", "rc", "hyp"],
        )
        w.writeheader()
        w.writerows(rows)

    agg = aggregate(rows)
    print(f"\n=== SUMMARY [{args.label}] ===")
    print(json.dumps(agg, indent=2))
    print(f"CSV -> {args.out}")
    if agg["failures"]:
        print(f"!! {agg['failures']} clip(s) FAILED — accuracy numbers are partial.", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
