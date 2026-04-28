"""Utilities for normalizing Nuclei scan output.

Converts the raw JSON Nuclei produces into the simplified, seed-document
shape consumed by the SLO tracking component. The reference shape lives in
``.claude/docs/normalized_sample.json`` and the field contract lives in
``Normalized JSON Output`` of the seed document.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Dict, List, Mapping, Sequence, Union


def _coerce_to_entries(raw: Union[Mapping[str, Any], Sequence[Mapping[str, Any]]]) -> List[Dict[str, Any]]:
    """Normalize the raw JSON structure into a list of dictionaries.

    Nuclei can emit scan results as a sequence (``[{}, {}, ...]``) or as
    newline-delimited JSON objects that some callers pre-load one at a
    time. Accepting both forms means we can feed in data as it was read
    without forcing extra wrapping logic.
    """

    # Single-object input → wrap it in a one-element list so downstream code
    # can always assume "list of entries".
    if isinstance(raw, Mapping):
        return [dict(raw)]

    # Sequence input → walk each item, defensively reject anything that is
    # not a dict-like mapping (catches malformed callers early).
    if isinstance(raw, Sequence):
        entries: List[Dict[str, Any]] = []
        for item in raw:
            if not isinstance(item, Mapping):
                raise TypeError("Each entry in the raw Nuclei data must be a mapping/dict.")
            entries.append(dict(item))
        return entries

    # Anything else (scalar, None, custom object) is a programmer error —
    # surface it loudly instead of silently returning [].
    raise TypeError("Raw Nuclei data must be a mapping or a sequence of mappings.")


def _clean_text(value: Any) -> str:
    """Return a human-friendly string representation for JSON fields."""

    # None → empty string keeps the output schema stable (every field always
    # present) without having to sprinkle null-checks across consumers.
    if value is None:
        return ""

    # For real strings, collapse runs of whitespace (newlines, tabs, double
    # spaces) into single spaces so multi-line Nuclei descriptions render
    # cleanly when emitted to JSON.
    if isinstance(value, str):
        return " ".join(value.split())

    # Numbers, bools, etc. → coerce via str(). Keeps the field a string per
    # the seed-doc contract regardless of what Nuclei put in the raw field.
    return str(value)


def _convert_entry(entry: Mapping[str, Any]) -> Dict[str, Any]:
    """Convert a single Nuclei JSON object into the normalized shape.

    Field names match the ``Normalized JSON Output`` table in the seed
    document. ``info.name`` and ``info.severity`` are emitted as a nested
    object, mirroring the raw Nuclei structure. The fallback chains for
    ``host`` / ``matched-at`` / ``template-id`` cover historical Nuclei
    field-name variance (e.g. ``templateID`` vs ``template-id``).
    """

    # Pull the nested `info` block once. If it is missing or not a dict
    # (older Nuclei or hand-edited input), substitute an empty dict so the
    # `.get()` calls below still work without TypeError.
    info = entry.get("info") if isinstance(entry.get("info"), Mapping) else {}

    # Description preference: full `info.description` first, then fall back
    # to the shorter `info.name` if no description was emitted by the
    # template (some Nuclei templates omit description entirely).
    description = info.get("description") or info.get("name")

    # Build the normalized record. Each `or` chain tolerates Nuclei version
    # drift: e.g. older outputs use `templateID` (camelCase) while current
    # Nuclei uses `template-id`; `host` may be absent and `url` carries the
    # value instead.
    return {
        "timestamp": _clean_text(entry.get("timestamp")),
        "host": _clean_text(entry.get("host") or entry.get("url") or entry.get("matched-at")),
        "template-id": _clean_text(entry.get("template-id") or entry.get("templateID")),
        "matched-at": _clean_text(entry.get("matched-at") or entry.get("url")),
        "description": _clean_text(description),
        "info": {
            "name": _clean_text(info.get("name")),
            "severity": _clean_text(info.get("severity")),
        },
    }


def convert_nuclei_raw(raw_data: Union[Mapping[str, Any], Sequence[Mapping[str, Any]]]) -> List[Dict[str, Any]]:
    """Convert in-memory Nuclei JSON data into the normalized shape."""

    # Coerce → uniform list, then map each entry through the converter.
    entries = _coerce_to_entries(raw_data)
    return [_convert_entry(item) for item in entries]


def convert_nuclei_raw_file(path: Union[str, Path]) -> List[Dict[str, Any]]:
    """Load a JSON file (single object or array) and normalize it.

    For newline-delimited JSON output produced by Nuclei, use
    :func:`convert_nuclei_jsonl_file` instead.
    """

    # Read the entire file as one JSON document (object or array) and hand
    # off to the in-memory converter.
    json_path = Path(path)
    with json_path.open("r", encoding="utf-8") as handle:
        raw = json.load(handle)
    return convert_nuclei_raw(raw)


def convert_nuclei_jsonl_file(path: Union[str, Path]) -> List[Dict[str, Any]]:
    """Load a Nuclei JSONL file and normalize each finding.

    JSONL = one JSON object per line. Blank lines are skipped. Malformed
    lines raise ``ValueError`` with the line number so debugging a bad
    scan output file does not require manual hex-dumping.
    """

    json_path = Path(path)
    entries: List[Dict[str, Any]] = []

    # Stream the file line-by-line. Iterating the file handle keeps memory
    # usage flat even for large scan outputs (millions of findings).
    with json_path.open("r", encoding="utf-8") as handle:
        for lineno, line in enumerate(handle, start=1):
            # Skip blank/whitespace-only lines — Nuclei occasionally emits
            # trailing newlines, and operators sometimes hand-edit files.
            stripped = line.strip()
            if not stripped:
                continue

            # Parse this single line as JSON. Failure: re-raise as
            # ValueError tagged with the line number so the operator can
            # jump straight to the bad line.
            try:
                obj = json.loads(stripped)
            except json.JSONDecodeError as exc:
                raise ValueError(f"Malformed JSON in {json_path} at line {lineno}: {exc}") from exc

            # Each line must decode to an object (Nuclei never emits
            # arrays/scalars per line); reject anything else loudly.
            if not isinstance(obj, Mapping):
                raise TypeError(f"{json_path} line {lineno}: expected a JSON object, got {type(obj).__name__}")

            # Normalize the parsed object and append to the result list.
            entries.append(_convert_entry(obj))

    return entries


def consolidate_jsonl_dir(directory: Union[str, Path]) -> List[Dict[str, Any]]:
    """Consolidate every ``*.jsonl`` file in ``directory`` into one list.

    Files are processed in sorted filename order so the consolidated
    output is deterministic regardless of filesystem iteration order.
    """

    # Verify the path is actually a directory before globbing. A typo in
    # the caller's path otherwise produces an empty result silently.
    dir_path = Path(directory)
    if not dir_path.is_dir():
        raise NotADirectoryError(f"Not a directory: {dir_path}")

    # Walk *.jsonl files in sorted order, normalize each, and concatenate.
    # Sorted order = deterministic output across runs and platforms.
    consolidated: List[Dict[str, Any]] = []
    for jsonl_file in sorted(dir_path.glob("*.jsonl")):
        consolidated.extend(convert_nuclei_jsonl_file(jsonl_file))
    return consolidated
