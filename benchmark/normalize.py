"""Croatian-aware text normalization for WER/CER benchmarking.

Pinned and deterministic. Applied to BOTH reference and hypothesis before
scoring, so the metric measures real transcription errors, not formatting noise.

Policy v1 (see docs/specs/phase-1-whisper-setup.md §5.4):
- Unicode NFC.
- Casefold to lowercase (preserves Croatian diacritics č ć š ž đ).
- Replace punctuation/symbols with spaces (keep letters, combining marks, digits).
- Collapse whitespace; strip.
- Numbers are left as-is (digit-vs-word is a documented v1 limitation; refine later).
"""
import re
import unicodedata

# Drop anything that is not a word character (letters incl. diacritics, digits,
# underscore) or whitespace — i.e. strip punctuation/symbols.
_PUNCT = re.compile(r"[^\w\s]", flags=re.UNICODE)
_WS = re.compile(r"\s+", flags=re.UNICODE)


def normalize(text: str) -> str:
    if not text:
        return ""
    t = unicodedata.normalize("NFC", text)
    t = t.casefold()
    t = _PUNCT.sub(" ", t)
    t = _WS.sub(" ", t)
    return t.strip()
