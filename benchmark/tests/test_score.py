from score import score


def test_identical_is_zero():
    r = score("Ovo je test.", "ovo je test")
    assert r["wer"] == 0.0
    assert r["cer"] == 0.0


def test_only_case_and_punct_differ_is_zero():
    r = score("Idem u Kuću!", "idem u kuću")
    assert r["wer"] == 0.0


def test_one_word_substitution():
    # 4 reference words, 1 substitution -> WER 0.25
    r = score("a b c d", "a b x d")
    assert abs(r["wer"] - 0.25) < 1e-9


def test_empty_hypothesis_is_total_error():
    r = score("jedan dva tri", "")
    assert r["wer"] == 1.0


def test_ref_words_count():
    r = score("jedan dva tri", "jedan dva tri")
    assert r["ref_words"] == 3


def test_empty_reference_nonempty_hypothesis_is_full_error():
    # The hand-written empty-ref branch is the only scorer logic NOT delegated
    # to jiwer — pin it (QA 2026-07-08).
    r = score("", "nesto")
    assert r["wer"] == 1.0
    assert r["cer"] == 1.0
    assert r["ref_words"] == 0


def test_empty_reference_empty_hypothesis_is_perfect():
    r = score("", "")
    assert r["wer"] == 0.0
    assert r["cer"] == 0.0
    assert r["ref_words"] == 0


def test_punctuation_only_reference_normalizes_to_empty():
    # normalize() strips punctuation, so a "..." reference hits the empty-ref
    # branch even though the raw string is non-empty.
    r = score("!!!", "hm")
    assert r["wer"] == 1.0
    assert r["ref_words"] == 0
