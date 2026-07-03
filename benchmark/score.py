"""CER/WER scoring with the pinned Croatian normalization.

Gate metric is WER (ADR-003); CER is reported alongside for stability.
"""
import jiwer

from normalize import normalize


def score(reference: str, hypothesis: str) -> dict:
    """Return {'wer', 'cer', 'ref_words'} for one (reference, hypothesis) pair.

    Both are normalized first. Edge cases are handled explicitly so jiwer is
    never asked to divide by an empty reference.
    """
    ref = normalize(reference)
    hyp = normalize(hypothesis)

    if ref == "":
        # No reference words: perfect only if the hypothesis is also empty.
        wer = 0.0 if hyp == "" else 1.0
        cer = 0.0 if hyp == "" else 1.0
        return {"wer": wer, "cer": cer, "ref_words": 0}

    return {
        "wer": float(jiwer.wer(ref, hyp)),
        "cer": float(jiwer.cer(ref, hyp)),
        "ref_words": len(ref.split()),
    }
