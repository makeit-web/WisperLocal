"""Download FLEURS-hr and emit 16 kHz mono WAVs + a manifest.json.

FLEURS audio is already 16 kHz mono. We avoid the heavy `torchcodec`/`torch`
dependency that `datasets>=5` wants for audio decoding by casting the audio
column to `decode=False` and decoding the raw bytes with soundfile ourselves.

Usage:
  python prepare_fleurs.py --out data/fleurs-hr --split test [--limit N]
"""
import argparse
import io
import json
import os

import soundfile as sf


def load_fleurs(split: str):
    from datasets import Audio, load_dataset

    # No trust_remote_code fallback: it would download and EXECUTE the dataset
    # repo's current loading script from the Hub — unpinned remote code — on any
    # transient failure of the plain path (QA 2026-07-08). Modern `datasets`
    # serves google/fleurs from the parquet auto-conversion without a script;
    # if this load fails, fix the datasets version instead of escalating.
    try:
        ds = load_dataset("google/fleurs", "hr_hr", split=split)
    except Exception as e:  # noqa: BLE001
        raise RuntimeError(
            "FLEURS load failed. Do NOT retry with trust_remote_code=True; "
            "upgrade the 'datasets' package (parquet path) instead.\n  "
            f"{type(e).__name__}: {e}"
        ) from e
    # Do not let datasets decode audio (would require torchcodec).
    return ds.cast_column("audio", Audio(decode=False))


def _read_audio(entry: dict):
    """Return (array, samplerate) from a decode=False audio entry."""
    if entry.get("bytes"):
        return sf.read(io.BytesIO(entry["bytes"]))
    return sf.read(entry["path"])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="data/fleurs-hr")
    ap.add_argument("--split", default="test")
    ap.add_argument("--limit", type=int, default=0)
    args = ap.parse_args()

    ds = load_fleurs(args.split)
    print(f"FLEURS-hr {args.split}: {len(ds)} examples; fields: {list(ds.features)}")

    audio_dir = os.path.join(args.out, "audio")
    os.makedirs(audio_dir, exist_ok=True)
    n = len(ds) if not args.limit else min(args.limit, len(ds))
    items = []
    sr_seen = None
    for i in range(n):
        ex = ds[i]
        arr, sr = _read_audio(ex["audio"])
        sr_seen = sr
        ref = ex.get("raw_transcription") or ex.get("transcription") or ""
        wav = os.path.join(audio_dir, f"{i:04d}.wav")
        sf.write(wav, arr, sr, subtype="PCM_16")
        items.append({"audio": wav, "ref": ref})

    with open(os.path.join(args.out, "manifest.json"), "w") as f:
        json.dump(items, f, ensure_ascii=False, indent=1)
    print(f"wrote {len(items)} samples to {args.out} (sample_rate={sr_seen})")


if __name__ == "__main__":
    main()
