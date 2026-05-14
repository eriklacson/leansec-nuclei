## Plan — Normalized JSON Wrapper (sprint `update/normalize_json_wrapper`)

For architect review before implementation. Sprint reference: `.claude/sprint.md`. Scope: `.claude/scope.md`. ADR-007 boundaries respected (scanner layer only).

---

### 1. File-by-file change list

#### 1.1 `scanner/nuclei_json_converter.py`

**Top of file (after imports, before helpers)** — add the module constant:

```python
SCHEMA_VERSION = 1
```

**Module docstring (lines 1–7)** — broaden per sprint Task 7. Replace:

> "Converts the raw JSON Nuclei produces into the simplified, seed-document shape consumed by the SLO tracking component."

with:

> "Converts the raw JSON Nuclei produces into the v1 normalized JSON contract consumed by external integrations. The reference shape lives in `.claude/docs/normalized_sample.json` and the field contract lives in `Normalized JSON Output` of the seed document."

(Removes the LeanSecurity-specific "SLO tracking component" reference; the wrapper is general-purpose now.)

**Append after `consolidate_jsonl_dir` (currently ends at line 182):**

```python
def list_executed_profiles(directory: Path | str) -> list[str]:
    """Return profile names derived from *.jsonl filenames in directory.

    Filename convention: '<profile>_<YYYY-MM>.jsonl'. Returns the profile
    stems (filename without the trailing '_YYYY-MM.jsonl'), sorted.
    Raises NotADirectoryError if directory is not a directory.
    """
    # Guard: same contract as consolidate_jsonl_dir so callers see one
    # predictable failure mode when the path is wrong.
    dir_path = Path(directory)
    if not dir_path.is_dir():
        raise NotADirectoryError(f"Not a directory: {dir_path}")

    # Strip the trailing _YYYY-MM segment when it matches the canonical
    # filename convention; otherwise fall back to the bare stem so stray
    # *.jsonl files do not crash the pipeline.
    suffix_re = re.compile(r"_\d{4}-\d{2}$")

    profiles: set[str] = set()
    for jsonl_file in dir_path.glob("*.jsonl"):
        stem = jsonl_file.stem
        profiles.add(suffix_re.sub("", stem))

    return sorted(profiles)


def build_normalized_document(
    findings: list[dict],
    client: str,
    run_date: str,
    profiles_executed: list[str],
) -> dict:
    """Wrap a list of normalized findings into the v1 contract envelope.

    Returns a dict with `schema_version`, `scan_run`, and `findings` keys
    matching the external integration contract.
    """
    # Source schema_version from the module constant so updates flow from
    # one place — prevents accidental hardcoding drift across helpers.
    return {
        "schema_version": SCHEMA_VERSION,
        "scan_run": {
            "client": client,
            "run_date": run_date,
            "profiles_executed": sorted(profiles_executed),
            "findings_count": len(findings),
        },
        "findings": findings,
    }
```

Add `import re` near the existing `import json` line.

**Function is pure**: no I/O, no `datetime`, no env access. `sorted(profiles_executed)` returns a new list, leaving the caller's input untouched.

#### 1.2 `scanner/scan.py`

**Line 23** — extend the existing import:

```python
from nuclei_json_converter import (  # noqa: E402
    build_normalized_document,
    consolidate_jsonl_dir,
    list_executed_profiles,
)
```

**Variable-name collision flag** — `scan.py:89` already uses `findings` as an `int` line-tally counter. Sprint Task 3 instructs to rename the *list* `consolidated` → `findings`, which collides. Resolution: rename the existing `int` counter to `findings_count` (lines 89–92, 115). This aligns with the wrapper's own `findings_count` field name — semantically consistent.

**Lines 98–110** (the consolidate-and-write block) — replace with:

```python
consolidated_path = None
try:
    # Walk out_dir, normalize every JSONL line, concatenate to one list.
    findings = consolidate_jsonl_dir(out_dir)

    # Derive profile names from the *.jsonl files actually written by
    # this scan so the envelope reflects what ran, not what was defined.
    profiles_executed = list_executed_profiles(out_dir)

    # Filename uses today's date so multiple runs in the same month
    # produce distinct files instead of silently overwriting.
    run_date = datetime.now().strftime("%Y-%m-%d")

    # Wrap findings in the v1 envelope before serializing.
    document = build_normalized_document(
        findings=findings,
        client=client,
        run_date=run_date,
        profiles_executed=profiles_executed,
    )

    consolidated_path = out_dir / f"result-{run_date}.json"
    consolidated_path.write_text(json.dumps(document, indent=2), encoding="utf-8")
except Exception as exc:  # noqa: BLE001
    # Catch-all is deliberate: report and continue. Operator still
    # sees the scan summary and the raw JSONL is still on disk.
    print(f"\nWarning: failed to write consolidated JSON: {exc}")
```

The existing summary print (`f"Total findings: {findings}"` → updates to `findings_count`) still works because it tallies non-blank JSONL lines, independent of the wrapper.

#### 1.3 `scanner/nuclei_convert_tool.py`

**Line 23** — extend the import to add `build_normalized_document` and `list_executed_profiles`.

**Lines 70–81** — apply the same wrapper logic:

```python
findings = consolidate_jsonl_dir(input_dir)
profiles_executed = list_executed_profiles(input_dir)

run_date = datetime.now().strftime("%Y-%m-%d")
document = build_normalized_document(
    findings=findings,
    client=args.client,
    run_date=run_date,
    profiles_executed=profiles_executed,
)

output_path = input_dir / f"result-{run_date}.json"
output_path.write_text(json.dumps(document, indent=2), encoding="utf-8")

print(
    f"Wrote v1 normalized document with {len(findings)} finding(s) "
    f"across {len(profiles_executed)} profile(s)"
)
print(f"Output: {output_path}")
```

`run_date` stays `datetime.now()` (the tool's purpose is to produce a fresh run-date-stamped consolidated file from existing JSONL, per sprint Task 4).

#### 1.4 `tests/test_nuclei_json_converter.py`

Existing tests stay unchanged — `_convert_entry`, `convert_nuclei_raw`, `convert_nuclei_jsonl_file`, and `consolidate_jsonl_dir` still return finding-level data.

Add 10 new test functions (9 unit + 1 round-trip integration), all per sprint Tasks 5 and 6:

| # | Test | Asserts |
|---|------|---------|
| 1 | `test_build_normalized_document_basic_shape` | Keys are exactly `{schema_version, scan_run, findings}`; `schema_version == 1`; `findings` is the input list. |
| 2 | `test_build_normalized_document_scan_run_fields` | `scan_run` has exactly `{client, run_date, profiles_executed, findings_count}`; values match inputs; `findings_count == len(findings)`. |
| 3 | `test_build_normalized_document_sorts_profiles` | Input `["zeta","alpha","mike"]` → output `["alpha","mike","zeta"]`. |
| 4 | `test_build_normalized_document_empty_findings` | `findings=[]` → `findings_count == 0`, `findings == []`. |
| 5 | `test_build_normalized_document_uses_module_constant` | Output `schema_version == nuclei_json_converter.SCHEMA_VERSION`. |
| 6 | `test_list_executed_profiles_strips_month_suffix` | tmp_path with three canonical-named files → sorted bare stems. |
| 7 | `test_list_executed_profiles_handles_irregular_filenames` | Mix canonical + bare `weird-leftover.jsonl` → both stems present, no raise. |
| 8 | `test_list_executed_profiles_empty_directory` | Empty tmp_path → `[]`. |
| 9 | `test_list_executed_profiles_not_a_directory` | Non-existent path → `NotADirectoryError`. |
| 10 | `test_consolidate_and_wrap_round_trip` | Two JSONL files (3 findings total) → full envelope assertions including finding-shape sanity check. |

All tests use the existing `sys.path.insert(...)` import pattern. No new dependencies.

---

### 2. Order of execution

1. Add `SCHEMA_VERSION`, `import re`, `list_executed_profiles`, `build_normalized_document`, and docstring update to `nuclei_json_converter.py`.
2. Add the new tests in `test_nuclei_json_converter.py` and run pytest — confirm they pass against the converter changes alone (no scan.py / convert_tool.py changes yet).
3. Update `scan.py` (rename `findings` int → `findings_count`, plug in wrapper logic, extend import).
4. Update `nuclei_convert_tool.py` (extend import, plug in wrapper logic, update summary).
5. Run full gate: `black --check .` → `ruff check .` → `bandit -r . --severity-level high` → `pytest`.
6. Manual end-to-end on an existing client deployment to confirm the on-disk shape matches the contract.

This order means the test suite is green at every commit boundary, and any breakage in `scan.py` / `nuclei_convert_tool.py` is caught by the new round-trip test before integration.

---

### 3. Risks and mitigations

| Risk | Mitigation |
|---|---|
| `findings` name collision in `scan.py` (existing `int`, new `list`). | Rename existing counter to `findings_count` — matches the wrapper's field name and removes the collision. Flagged explicitly to the architect since sprint Task 3 does not name this conflict. |
| `list_executed_profiles` glob picks up `result-YYYY-MM-DD.json`? | `.glob("*.jsonl")` only matches `.jsonl` files. The wrapper JSON (`.json`) is not matched. No issue. |
| Re-running `scan.py` in the same month overwrites the previous day's `result-YYYY-MM-DD.json`? | Same behavior as today — filename is run-date-stamped, so same-day re-runs overwrite. Not in scope to change. |
| Stray `.jsonl` left in a results dir from a prior run with a different filename convention. | `list_executed_profiles` uses defensive regex (`r"_\d{4}-\d{2}$"`) and falls back to the bare stem. The set dedupe handles duplicate stems if a stray file overlaps a canonical one. |
| `bandit -r . --severity-level high` flag — sprint says exactly that string; CLAUDE.md `Commands` section says `bandit -r . -x ".venv,..."` (no severity flag). | Follow the sprint's verification recipe verbatim during VERIFY. Both invocations should pass since no new high-severity surface is introduced. |
| ADR-007 boundary — could the wrapper inadvertently couple scanner to docker/infra? | The wrapper is pure data — no I/O, no env. Stays inside `scanner/`. Boundary preserved. |

---

### 4. Assumptions (call out before implementing)

1. **No existing `result-YYYY-MM-DD.json` consumers in this repo to migrate**. The sprint says the bare-array shape is retired entirely with no compat mode. Searched — no Python code in the repo reads `result-*.json` (only writes it). Confirmed safe.
2. **`run_date` stays `datetime.now()`** in both `scan.py` and `nuclei_convert_tool.py`. Sprint Task 4 explicitly endorses this for the convert tool. The function itself stays pure (callers compute the date).
3. **`SCHEMA_VERSION = 1` as `int`**. Sprint says "integer literal `1`" and verification step 2 specifies "integer, not string". Confirmed.
4. **No changes to raw JSONL writes** — only the consolidation output changes. The seven per-profile `.jsonl` files are untouched.
5. **The seed-doc §3 "Normalized JSON Output" field table is finding-level only**, not envelope-level. The new envelope keys (`schema_version`, `scan_run.*`) are not yet documented in the seed doc. The sprint does not require a seed-doc revision for this change. **Confirm with architect** whether a seed-doc delta is expected, or whether this lands purely as scanner-layer work.

---

### 5. Open questions (architect to resolve)

1. **Seed-doc revision** — see Assumption 5. Should this work include a delta in `.claude/docs/` documenting the v1 envelope, or defer to the next planned seed-doc rev?
2. **Comment density on new code** — my memory has a project rule that "every code block needs a semi-pseudocode comment" overriding default no-comments policy. The plan above follows that. Confirm this rule still applies to scanner-layer code in this sprint.
3. **CLAUDE.md path drift** (flagged in scope) — the file references `claude-project/LeanSecurity_Nuclei_Seed_Document.md` but the seed doc lives at `.claude/docs/LeanSecurity_Nuclei_seed_document.md`. Want me to fold a one-line CLAUDE.md fix into this branch, or open a separate task?

---

### 6. Out of scope (explicit, per sprint §"Out of scope")

Not touching: `scan_run.scan_started_at`, `scan_run.scan_completed_at`, `scan_run.scanner_version`, backward-compat for the bare-array shape, schema validation in the consumer direction, raw JSONL output, `profiles.yaml`, `entrypoint.sh`, Terraform, `.docx` quickstart/implementation guides.
