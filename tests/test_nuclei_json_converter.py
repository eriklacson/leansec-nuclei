import json
import sys
from pathlib import Path

import pytest

# scanner/ is not a package, so add it to sys.path before importing the
# module under test. Same convention as tests/test_nuclei_helpers.py.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "scanner"))
import nuclei_json_converter  # noqa: E402


def test_convert_entry_emits_seed_doc_shape():
    """Normalized output should match the seed document field contract."""

    # Build a fully-populated raw Nuclei entry — nested info block, all
    # current field names — to verify the canonical happy-path mapping.
    raw_entries = [
        {
            "template-id": "tpl-1",
            "host": "https://example.com",
            "matched-at": "https://example.com/path",
            "timestamp": "2024-01-01T00:00:00Z",
            "info": {
                "severity": "medium",
                "description": "Example finding",
                "name": "example-matcher",
                "tags": ["ssl", "tls"],
            },
        }
    ]

    # Run through the public converter and unpack the (single) result.
    [normalized] = nuclei_json_converter.convert_nuclei_raw(raw_entries)

    # Assert exact equality on the full record. Catches accidental field
    # additions, removals, renames, or shape changes (e.g. nested → flat).
    assert normalized == {
        "timestamp": "2024-01-01T00:00:00Z",
        "host": "https://example.com",
        "template-id": "tpl-1",
        "matched-at": "https://example.com/path",
        "description": "Example finding",
        "info": {
            "name": "example-matcher",
            "severity": "medium",
        },
    }


def test_convert_entry_falls_back_when_fields_missing():
    """Legacy Nuclei field names and missing info should not crash."""

    # Use the legacy camelCase `templateID` and `url` (instead of `host`)
    # to verify the fallback chains in _convert_entry handle older Nuclei.
    raw_entries = [
        {
            "templateID": "legacy-tpl",
            "url": "https://legacy.example.com",
            "timestamp": "2024-02-02T00:00:00Z",
        }
    ]

    [normalized] = nuclei_json_converter.convert_nuclei_raw(raw_entries)

    # Each fallback should resolve: legacy templateID → template-id, url
    # → both host and matched-at, missing info → empty nested fields.
    assert normalized["template-id"] == "legacy-tpl"
    assert normalized["host"] == "https://legacy.example.com"
    assert normalized["matched-at"] == "https://legacy.example.com"
    assert normalized["info"] == {"name": "", "severity": ""}


def test_convert_nuclei_jsonl_file_parses_line_by_line(tmp_path: Path):
    """Each non-blank line in a JSONL file should produce one finding."""

    # Construct a JSONL fixture that includes blank and whitespace-only
    # lines between real entries — those should be skipped silently.
    jsonl = tmp_path / "scan.jsonl"
    jsonl.write_text(
        "\n".join(
            [
                json.dumps({"template-id": "a", "info": {"severity": "low", "name": "n1"}}),
                "",
                "   ",
                json.dumps({"template-id": "b", "info": {"severity": "high", "name": "n2"}}),
            ]
        ),
        encoding="utf-8",
    )

    # Parse the file and verify only the two real entries came through,
    # in the order they appeared in the source file.
    result = nuclei_json_converter.convert_nuclei_jsonl_file(jsonl)

    assert [entry["template-id"] for entry in result] == ["a", "b"]
    assert result[0]["info"] == {"name": "n1", "severity": "low"}


def test_convert_nuclei_jsonl_file_raises_on_malformed_line(tmp_path: Path):
    """Malformed lines should raise ValueError with the line number."""

    # Write a JSONL fixture where line 1 is valid but line 2 is broken.
    # We expect the parser to point at line 2 in the error message so an
    # operator can locate the bad data without manual file inspection.
    jsonl = tmp_path / "scan.jsonl"
    jsonl.write_text(
        "\n".join(
            [
                json.dumps({"template-id": "a"}),
                "{not valid json",
            ]
        ),
        encoding="utf-8",
    )

    # ValueError must mention "line 2" — both the type and the message
    # form a contract for log-grep tooling and human debuggers.
    with pytest.raises(ValueError, match="line 2"):
        nuclei_json_converter.convert_nuclei_jsonl_file(jsonl)


def test_consolidate_jsonl_dir_concatenates_in_sorted_order(tmp_path: Path):
    """Output ordering should follow sorted filenames for determinism."""

    # Write `b.jsonl` first to deliberately give it a later mtime, then
    # `a.jsonl`. The function must still process `a` before `b` because
    # ordering is by filename, not filesystem creation order.
    (tmp_path / "b.jsonl").write_text(
        json.dumps({"template-id": "b1"}) + "\n",
        encoding="utf-8",
    )
    (tmp_path / "a.jsonl").write_text(
        json.dumps({"template-id": "a1"}) + "\n" + json.dumps({"template-id": "a2"}) + "\n",
        encoding="utf-8",
    )

    # Consolidated output should be a1, a2 (both from a.jsonl, in file
    # order), then b1 (from b.jsonl) — i.e. sorted by filename.
    result = nuclei_json_converter.consolidate_jsonl_dir(tmp_path)

    assert [entry["template-id"] for entry in result] == ["a1", "a2", "b1"]


def test_consolidate_jsonl_dir_empty_dir_returns_empty_list(tmp_path: Path):
    """A directory with no JSONL files should return [] (not error)."""

    # Empty directory is a valid (if uninteresting) scan result — the
    # consolidator should return [] so the caller can still serialize
    # an empty array file rather than crashing.
    result = nuclei_json_converter.consolidate_jsonl_dir(tmp_path)

    assert result == []


def test_consolidate_jsonl_dir_rejects_non_directory(tmp_path: Path):
    """Passing a non-directory path should raise NotADirectoryError."""

    # Build a path under tmp_path that does not exist. is_dir() returns
    # False, so the function should fail loudly rather than glob nothing
    # (which would silently produce []).
    not_a_dir = tmp_path / "missing"

    with pytest.raises(NotADirectoryError):
        nuclei_json_converter.consolidate_jsonl_dir(not_a_dir)


# ---------------------------------------------------------------------------
# build_normalized_document — v1 envelope contract
# ---------------------------------------------------------------------------


def _sample_findings() -> list:
    """One minimally-shaped finding, reused across envelope tests."""

    # Match the shape produced by _convert_entry so tests reflect the real
    # data the envelope wraps in production.
    return [
        {
            "timestamp": "2026-04-30T14:23:11Z",
            "host": "https://app.example.com",
            "template-id": "tls-version",
            "matched-at": "https://app.example.com:443",
            "description": "TLS 1.0 is enabled on the target host",
            "info": {"name": "tls-version", "severity": "medium"},
        }
    ]


def test_build_normalized_document_basic_shape():
    """Envelope must have exactly schema_version, scan_run, findings."""

    # Build the envelope and capture the keys at the top level. The
    # contract pins the exact set — any drift (added keys, missing keys)
    # would break external consumers.
    findings = _sample_findings()
    document = nuclei_json_converter.build_normalized_document(
        findings=findings,
        client="acme",
        run_date="2026-04-30",
        profiles_executed=["baseline_web"],
    )

    assert set(document.keys()) == {"schema_version", "scan_run", "findings"}
    assert document["schema_version"] == 1
    # The findings list passes through unchanged — the envelope wraps,
    # it does not transform.
    assert document["findings"] == findings


def test_build_normalized_document_scan_run_fields():
    """scan_run must have exactly the four contract fields, matching inputs."""

    # Use distinctive values for each field so a mis-mapping (e.g., client
    # written to run_date) is caught by the assertion, not silently
    # ignored.
    findings = _sample_findings()
    document = nuclei_json_converter.build_normalized_document(
        findings=findings,
        client="acme",
        run_date="2026-04-30",
        profiles_executed=["baseline_web", "patch_cve"],
    )

    scan_run = document["scan_run"]
    assert set(scan_run.keys()) == {"client", "run_date", "profiles_executed", "findings_count"}
    assert scan_run["client"] == "acme"
    assert scan_run["run_date"] == "2026-04-30"
    assert scan_run["profiles_executed"] == ["baseline_web", "patch_cve"]
    # findings_count is derived from the findings list — verify the
    # invariant rather than re-asserting len() of the input.
    assert scan_run["findings_count"] == len(findings)


def test_build_normalized_document_sorts_profiles():
    """profiles_executed in the envelope must be sorted regardless of input order."""

    # Pass profiles out of order; the envelope should sort them so output
    # is deterministic for downstream diffs and snapshots.
    document = nuclei_json_converter.build_normalized_document(
        findings=[],
        client="acme",
        run_date="2026-04-30",
        profiles_executed=["zeta", "alpha", "mike"],
    )

    assert document["scan_run"]["profiles_executed"] == ["alpha", "mike", "zeta"]


def test_build_normalized_document_empty_findings():
    """Zero findings is a valid scan result — envelope must still be well-formed."""

    # Edge case: a clean scan finds nothing. The envelope must report
    # findings_count == 0 and findings == [] so consumers can rely on
    # the keys always being present.
    document = nuclei_json_converter.build_normalized_document(
        findings=[],
        client="acme",
        run_date="2026-04-30",
        profiles_executed=["baseline_web"],
    )

    assert document["scan_run"]["findings_count"] == 0
    assert document["findings"] == []


def test_build_normalized_document_uses_module_constant():
    """schema_version in the output must equal nuclei_json_converter.SCHEMA_VERSION."""

    # Guards against hardcoding drift — if SCHEMA_VERSION is bumped but
    # build_normalized_document still emits the literal, this test fails
    # immediately rather than at the next consumer integration.
    document = nuclei_json_converter.build_normalized_document(
        findings=[],
        client="acme",
        run_date="2026-04-30",
        profiles_executed=[],
    )

    assert document["schema_version"] == nuclei_json_converter.SCHEMA_VERSION


# ---------------------------------------------------------------------------
# list_executed_profiles — derive profile names from JSONL filenames
# ---------------------------------------------------------------------------


def test_list_executed_profiles_strips_month_suffix(tmp_path: Path):
    """Canonical filenames should yield bare profile stems, sorted."""

    # Write three canonically-named files. The function should strip the
    # trailing _YYYY-MM segment and return the bare profile names sorted.
    for name in ("baseline_web_2026-04.jsonl", "patch_cve_2026-04.jsonl", "transport_security_2026-04.jsonl"):
        (tmp_path / name).write_text("", encoding="utf-8")

    result = nuclei_json_converter.list_executed_profiles(tmp_path)

    assert result == ["baseline_web", "patch_cve", "transport_security"]


def test_list_executed_profiles_handles_irregular_filenames(tmp_path: Path):
    """Filenames without the _YYYY-MM suffix should fall back to the bare stem."""

    # Mix one canonical filename with one stray file that does not match
    # the convention. The function must not raise — it should include the
    # bare stem so an operator sees the unexpected file in the output.
    (tmp_path / "baseline_web_2026-04.jsonl").write_text("", encoding="utf-8")
    (tmp_path / "weird-leftover.jsonl").write_text("", encoding="utf-8")

    result = nuclei_json_converter.list_executed_profiles(tmp_path)

    assert "baseline_web" in result
    assert "weird-leftover" in result


def test_list_executed_profiles_empty_directory(tmp_path: Path):
    """An empty results directory should return [] (not error)."""

    # Empty directory is a valid (if uninteresting) intermediate state —
    # consumer code can serialize an envelope with profiles_executed=[].
    result = nuclei_json_converter.list_executed_profiles(tmp_path)

    assert result == []


def test_list_executed_profiles_not_a_directory(tmp_path: Path):
    """Non-existent path must raise NotADirectoryError, matching consolidate_jsonl_dir."""

    # Use a path under tmp_path that does not exist. The contract mirrors
    # consolidate_jsonl_dir so the two scanner helpers fail the same way
    # when handed a bad path.
    not_a_dir = tmp_path / "missing"

    with pytest.raises(NotADirectoryError):
        nuclei_json_converter.list_executed_profiles(not_a_dir)


# ---------------------------------------------------------------------------
# Round-trip — consolidate → list profiles → wrap
# ---------------------------------------------------------------------------


def test_consolidate_and_wrap_round_trip(tmp_path: Path):
    """Full path from raw JSONL on disk to v1 envelope must hold the contract."""

    # Build two canonically-named JSONL files with a total of 3 findings
    # across 2 profiles. This exercises consolidate_jsonl_dir,
    # list_executed_profiles, and build_normalized_document in the same
    # sequence scan.py uses in production.
    baseline = tmp_path / "baseline_web_2026-04.jsonl"
    baseline.write_text(
        "\n".join(
            [
                json.dumps(
                    {
                        "template-id": "bw-1",
                        "host": "https://a.example.com",
                        "matched-at": "https://a.example.com/x",
                        "timestamp": "2026-04-01T00:00:00Z",
                        "info": {"name": "n1", "severity": "low", "description": "d1"},
                    }
                ),
                json.dumps(
                    {
                        "template-id": "bw-2",
                        "host": "https://a.example.com",
                        "matched-at": "https://a.example.com/y",
                        "timestamp": "2026-04-01T00:00:01Z",
                        "info": {"name": "n2", "severity": "medium", "description": "d2"},
                    }
                ),
            ]
        )
        + "\n",
        encoding="utf-8",
    )
    transport = tmp_path / "transport_security_2026-04.jsonl"
    transport.write_text(
        json.dumps(
            {
                "template-id": "ts-1",
                "host": "https://b.example.com",
                "matched-at": "https://b.example.com:443",
                "timestamp": "2026-04-01T00:00:02Z",
                "info": {"name": "n3", "severity": "high", "description": "d3"},
            }
        )
        + "\n",
        encoding="utf-8",
    )

    # Run the same sequence scan.py runs.
    findings = nuclei_json_converter.consolidate_jsonl_dir(tmp_path)
    profiles_executed = nuclei_json_converter.list_executed_profiles(tmp_path)
    result = nuclei_json_converter.build_normalized_document(
        findings=findings,
        client="testclient",
        run_date="2026-04-30",
        profiles_executed=profiles_executed,
    )

    # Envelope-level assertions from sprint Task 6.
    assert result["schema_version"] == 1
    assert result["scan_run"]["client"] == "testclient"
    assert result["scan_run"]["run_date"] == "2026-04-30"
    assert result["scan_run"]["profiles_executed"] == ["baseline_web", "transport_security"]
    assert result["scan_run"]["findings_count"] == 3
    assert len(result["findings"]) == 3
    # Finding-level sanity check — confirms the converter still produces
    # the per-finding shape inside the envelope (not just empty wrappers).
    first = result["findings"][0]
    assert set(first.keys()) == {"timestamp", "host", "template-id", "matched-at", "description", "info"}
    assert set(first["info"].keys()) == {"name", "severity"}
