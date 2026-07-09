import math

from run_bench import aggregate, rtf


def test_rtf_faster_than_realtime():
    assert rtf(5.0, 10.0) == 0.5


def test_rtf_slower_than_realtime():
    assert rtf(20.0, 10.0) == 2.0


def test_rtf_zero_duration_is_nan():
    assert math.isnan(rtf(1.0, 0.0))


def test_aggregate_means():
    rows = [
        {"wer": 0.1, "cer": 0.05, "rtf": 0.5},
        {"wer": 0.3, "cer": 0.15, "rtf": 1.5},
    ]
    a = aggregate(rows)
    assert a["n"] == 2
    assert abs(a["wer_mean"] - 0.2) < 1e-9
    assert abs(a["cer_mean"] - 0.10) < 1e-9
    assert abs(a["rtf_mean"] - 1.0) < 1e-9


def test_aggregate_ignores_nan_rtf():
    rows = [
        {"wer": 0.2, "cer": 0.1, "rtf": float("nan")},
        {"wer": 0.2, "cer": 0.1, "rtf": 1.0},
    ]
    a = aggregate(rows)
    assert abs(a["rtf_mean"] - 1.0) < 1e-9


def test_aggregate_excludes_failed_rows_and_counts_them():
    # A crashed whisper-cli (rc != 0) scores as WER=1.0 garbage; it must be
    # counted as a failure and kept OUT of the accuracy means (QA 2026-07-08:
    # ADR-003 model selection gates on these numbers).
    rows = [
        {"wer": 0.1, "cer": 0.05, "rtf": 0.5, "rc": 0},
        {"wer": 1.0, "cer": 1.0, "rtf": 0.1, "rc": -6},
    ]
    a = aggregate(rows)
    assert a["failures"] == 1
    assert a["n_scored"] == 1
    assert abs(a["wer_mean"] - 0.1) < 1e-9
    assert abs(a["cer_mean"] - 0.05) < 1e-9


def test_aggregate_rows_without_rc_stay_scored():
    # Back-compat: historical rows (no rc column) count as successes.
    rows = [{"wer": 0.2, "cer": 0.1, "rtf": 1.0}]
    a = aggregate(rows)
    assert a["failures"] == 0
    assert a["n_scored"] == 1
    assert abs(a["wer_mean"] - 0.2) < 1e-9


def test_aggregate_all_failed_reports_nan_means():
    import math
    rows = [{"wer": 1.0, "cer": 1.0, "rtf": 0.1, "rc": 1}]
    a = aggregate(rows)
    assert a["failures"] == 1
    assert a["n_scored"] == 0
    assert math.isnan(a["wer_mean"])
