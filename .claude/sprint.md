# Project Task

## Context

The normalized JSON output (`results/<client>/YYYY-MM/result-YYYY-MM-DD.json`) is currently a bare array of finding objects. We are introducing a versioned wrapper shape so external consumers (third-party SLO trackers, dashboards) can integrate against a stable, evolvable contract.

This is a **breaking change** to the on-disk shape of `result-*.json`. Existing files in any `results/` directory will need to be regenerated to match the new shape. The bare-array shape is being retired entirely; there is no backward-compatibility mode.

The change is scoped to the scanner layer only. No infrastructure, container, or deployment changes are needed.

## Reference: target shape

```json
{
  "schema_version": 1,
  "scan_run": {
    "client": "<client>",
    "run_date": "YYYY-MM-DD",
    "profiles_executed": ["baseline_web", "patch_cve", "..."],
    "findings_count": 42
  },
  "findings": [
    {
      "timestamp": "2026-04-30T14:23:11Z",
      "host": "https://app.example.com",
      "template-id": "tls-version",
      "matched-at": "https://app.example.com:443",
      "description": "TLS 1.0 is enabled on the target host",
      "info": {
        "name": "tls-version",
        "severity": "medium"
      }
    }
  ]
}
```
The finding object shape is **unchanged** — only the file's outer container changes.

## Architecture constraints (do not violate)

- All YAML parsing in the scanner layer happens in `nuclei_helpers.py`. This change does not touch YAML, but do not introduce any YAML-related logic into `nuclei_json_converter.py`.
- The scanner does not import from `docker/`, `infra/`, or any future component. No new dependencies on those layers.
- The scanner's runtime dependencies remain Python 3.12, `pyyaml`, and the `nuclei` binary on PATH. Do not add new third-party dependencies.
- The container entrypoint (`docker/entrypoint.sh`) remains bash and does not invoke `scan.py`. No entrypoint changes are needed for this work.

## Tasks

### Task 1 — Add a wrapper builder to `scanner/nuclei_json_converter.py`

Add a new public function:

```python
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
```

Requirements for this function:

- `schema_version` is the integer literal `1`.
- `scan_run.client` is the passed-in `client` string.
- `scan_run.run_date` is the passed-in `run_date` string. Do NOT compute it here. The caller is responsible.
- `scan_run.profiles_executed` is a list of strings. Sort it so output is deterministic.
- `scan_run.findings_count` is `len(findings)`.
- `findings` is the passed-in list, unchanged.
- The function is pure: no I/O, no environment access, no datetime calls.

Place this function alongside the existing converter functions, after `consolidate_jsonl_dir`.

Also add a module-level constant `SCHEMA_VERSION = 1` at the top of the file (after the imports, before the helper functions). Use it as the source of the literal in `build_normalized_document` rather than hardcoding `1` twice.

### Task 2 — Add a profile-name extraction helper

The `profiles_executed` list is derived from the JSONL filenames present in the results directory at consolidation time. Add this helper to `nuclei_json_converter.py`:

```python
def list_executed_profiles(directory: Path | str) -> list[str]:
    """Return profile names derived from *.jsonl filenames in directory.

    Filename convention: '<profile>_<YYYY-MM>.jsonl'. Returns the profile
    stems (filename without the trailing '_YYYY-MM.jsonl'), sorted.
    Raises NotADirectoryError if directory is not a directory.
    """
```

Implementation notes:

- Use `dir_path.glob("*.jsonl")` and strip the trailing `_YYYY-MM` segment using a regex or a string split on the last underscore.
- Be defensive: if a `.jsonl` file is named in a way that doesn't match the convention (e.g., a stray file someone dropped in), include the bare stem as-is rather than crashing. The seed document's filename convention is the contract, but we should not crash on irregular files.
- Sort the returned list.
- Do not hardcode `_YYYY-MM` literally — use a regex like `r"_\d{4}-\d{2}$"` to strip the suffix when present.

### Task 3 — Update `scanner/scan.py` to emit the wrapper

In `scan.py`, locate the consolidated-write block (currently writes `json.dumps(consolidated, indent=2)`). Replace it so the file content is the new wrapper shape.

Specifically, where the current code does roughly:

```python
consolidated = consolidate_jsonl_dir(out_dir)
run_date = datetime.now().strftime("%Y-%m-%d")
consolidated_path = out_dir / f"result-{run_date}.json"
consolidated_path.write_text(json.dumps(consolidated, indent=2), encoding="utf-8")
```

Change it to:

```python
findings = consolidate_jsonl_dir(out_dir)
run_date = datetime.now().strftime("%Y-%m-%d")
profiles_executed = list_executed_profiles(out_dir)
document = build_normalized_document(
    findings=findings,
    client=client,
    run_date=run_date,
    profiles_executed=profiles_executed,
)
consolidated_path = out_dir / f"result-{run_date}.json"
consolidated_path.write_text(json.dumps(document, indent=2), encoding="utf-8")
```

The local variable previously named `consolidated` should be renamed to `findings` to reflect that it's now the array, not the full document. Update the surrounding error-handling and logging lines to match (e.g., the `print(f"Total findings: ...")` line stays correct because it's based on a separate count, but check anything that referenced `consolidated` and adjust).

Make sure `list_executed_profiles` and `build_normalized_document` are added to the existing `from nuclei_json_converter import ...` line at the top of `scan.py`.

### Task 4 — Update `scanner/nuclei_convert_tool.py` to emit the wrapper

`nuclei_convert_tool.py` is the standalone CLI for re-consolidating JSONL into normalized JSON outside of a full scan. Apply the same wrapper logic:

- Use `list_executed_profiles(input_dir)` to get the profile list.
- Use `build_normalized_document(...)` to build the wrapper.
- Write the wrapper instead of the bare list.
- The `--month` argument is an existing flag that selects which month's directory to consolidate. The `run_date` should still be `datetime.now().strftime("%Y-%m-%d")` — this tool's purpose is to produce a fresh run-date-stamped consolidated file from existing JSONL.
- The `client` argument is already a positional CLI arg; pass it through.

Update the user-facing summary print at the end so it says something like "Wrote v1 normalized document with N findings across M profiles."

### Task 5 — Update tests in `tests/test_nuclei_json_converter.py`

The existing test `test_convert_entry_emits_seed_doc_shape` and others assert against bare finding objects produced by the converter functions. These tests should remain unchanged — `_convert_entry`, `convert_nuclei_raw`, `convert_nuclei_jsonl_file`, and `consolidate_jsonl_dir` still return finding-level data, not the wrapped document. The wrapper is only built by the new `build_normalized_document` function.

Add new tests covering:

1. **`test_build_normalized_document_basic_shape`** — call `build_normalized_document` with a minimal `findings` list (one finding), assert the returned dict has exactly the keys `schema_version`, `scan_run`, `findings`, with `schema_version == 1` and `findings` equal to the input list.

2. **`test_build_normalized_document_scan_run_fields`** — assert `scan_run` contains exactly `client`, `run_date`, `profiles_executed`, `findings_count`, with values matching the inputs and `findings_count == len(findings)`.

3. **`test_build_normalized_document_sorts_profiles`** — pass `profiles_executed=["zeta", "alpha", "mike"]` and assert the output list is `["alpha", "mike", "zeta"]`.

4. **`test_build_normalized_document_empty_findings`** — pass `findings=[]` and assert `findings_count == 0` and the `findings` array is `[]`.

5. **`test_build_normalized_document_uses_module_constant`** — assert the returned `schema_version` equals `nuclei_json_converter.SCHEMA_VERSION`. This catches accidental hardcoding drift if someone updates one but not the other.

6. **`test_list_executed_profiles_strips_month_suffix`** — create a tmp_path with files `baseline_web_2026-04.jsonl`, `patch_cve_2026-04.jsonl`, `transport_security_2026-04.jsonl`. Call `list_executed_profiles(tmp_path)` and assert the result is `["baseline_web", "patch_cve", "transport_security"]` (sorted).

7. **`test_list_executed_profiles_handles_irregular_filenames`** — create a tmp_path containing a normal `baseline_web_2026-04.jsonl` and an irregular `weird-leftover.jsonl` (no month suffix). Assert both stems appear in the output list and the function did not raise.

8. **`test_list_executed_profiles_empty_directory`** — call against an empty tmp_path; assert returns `[]`.

9. **`test_list_executed_profiles_not_a_directory`** — call against a path that is a file (or doesn't exist) and assert `NotADirectoryError`.

Use the same import-and-`sys.path` pattern the existing tests use.

### Task 6 — Verify the round-trip end-to-end

Add one integration-style test that exercises the full path from raw JSONL on disk to the wrapped document:

**`test_consolidate_and_wrap_round_trip`** — create a tmp_path with two JSONL files (`baseline_web_2026-04.jsonl` with two findings, `transport_security_2026-04.jsonl` with one finding). Call `consolidate_jsonl_dir` and `list_executed_profiles` to derive the inputs, then call `build_normalized_document` with `client="testclient"`, `run_date="2026-04-30"`. Assert:

- `result["schema_version"] == 1`
- `result["scan_run"]["client"] == "testclient"`
- `result["scan_run"]["run_date"] == "2026-04-30"`
- `result["scan_run"]["profiles_executed"] == ["baseline_web", "transport_security"]`
- `result["scan_run"]["findings_count"] == 3`
- `len(result["findings"]) == 3`
- `result["findings"][0]` has the expected normalized finding shape (`timestamp`, `host`, `template-id`, `matched-at`, `description`, `info`)

### Task 7 — Documentation comments

Update the module docstring at the top of `nuclei_json_converter.py` to mention that the module now also produces the v1 wrapper document. The existing docstring references "the seed-document shape consumed by the SLO tracking component" — broaden this to "the v1 normalized JSON contract consumed by external integrations" and remove the LeanSecurity-specific reference to "SLO tracking component" (the converter is now general-purpose).

Do not modify the implementation guide or local quickstart `.docx` files. Per project rules, those are pending re-draft and should not be regenerated piecemeal.

## Verification

Before considering the work complete, run the full CI gate from the repo root:

```bash
poetry run black --check .
poetry run ruff check .
poetry run bandit -r . --severity-level high
poetry run pytest
```

All four must pass. If any existing test fails because it asserted the bare-array shape, that test is in scope for this change — update it to match the new contract. Do not skip or `xfail` any test.

After the unit tests pass, do a manual end-to-end check:

```bash
poetry run python scanner/scan.py <some-existing-client>
```

Inspect the resulting `results/<client>/YYYY-MM/result-YYYY-MM-DD.json` and confirm:

- The top-level keys are exactly `schema_version`, `scan_run`, `findings`
- `schema_version` is `1` (integer, not string)
- `scan_run.client` matches the CLI argument
- `scan_run.run_date` matches today's date
- `scan_run.profiles_executed` lists every profile that produced a JSONL file
- `scan_run.findings_count` matches `len(findings)`
- `findings` array contents are unchanged from the previous bare-array shape

## Out of scope for this change

Do NOT implement any of the following — they are deferred to a future v1.x revision:

- `scan_run.scan_started_at` / `scan_run.scan_completed_at` timestamps
- `scan_run.scanner_version`
- Backward-compatibility mode for reading the old bare-array shape
- Schema version checking or validation in the consumer direction
- Any changes to raw JSONL output
- Any changes to `profiles.yaml`, `entrypoint.sh`, or Terraform modules
- Updates to `LeanSecurity_Nuclei_Implementation_Guide.docx` or `LeanSecurity_Nuclei_Local_Quickstart.docx`

If you encounter ambiguity that this prompt does not resolve, stop and ask before proceeding.