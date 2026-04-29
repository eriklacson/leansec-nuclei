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
