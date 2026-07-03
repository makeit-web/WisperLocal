from normalize import normalize


def test_lowercase_and_trailing_punct():
    assert normalize("Idem u Kuću.") == "idem u kuću"


def test_preserves_croatian_diacritics():
    assert normalize("Č, Ć, Š, Ž, Đ!") == "č ć š ž đ"


def test_collapses_whitespace_and_newlines():
    assert normalize("Ovo   je\n test ") == "ovo je test"


def test_digits_preserved():
    assert normalize("Imam 5 auta!") == "imam 5 auta"


def test_none_and_empty():
    assert normalize(None) == ""
    assert normalize("   ") == ""
