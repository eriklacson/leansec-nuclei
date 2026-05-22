# REPORT — Normalized JSON Wrapper (sprint `update/normalize_json_wrapper`)

## What shipped

**4 files modified, 1 added, +377 / −20 lines:**

| File | Change |
|---|---|
| `scanner/nuclei_json_converter.py` | `SCHEMA_VERSION = 1` constant; `import re`; `list_executed_profiles()`; `build_normalized_document()`; broadened module docstring (removed "SLO tracking component" reference per Task 7). |
| `scanner/scan.py` | Extended import to pull in `build_normalized_document` + `list_executed_profiles`; renamed `findings` int counter → `findings_count` (resolved name collision flagged in plan); plugged in envelope on the consolidation write path. |
| `scanner/nuclei_convert_tool.py` | Same envelope plug-in; updated summary print to `"Wrote v1 normalized document with N finding(s) across M profile(s)"`. |
| `tests/test_nuclei_json_converter.py` | 10 new tests: 5 for `build_normalized_document` (basic shape, scan_run fields, profile sort, empty findings, module-constant linkage), 4 for `list_executed_profiles` (canonical strip, irregular filenames, empty dir, NotADirectoryError), 1 end-to-end round-trip exercising consolidate → list → wrap. |

## Acceptance criteria check (sprint §Verification)

| Gate | Result |
|---|---|
| `poetry run black --check .` | PASS — 10 files unchanged |
| `poetry run ruff check .` | PASS — All checks passed |
| `poetry run bandit -r . --severity-level high` | PASS — 0 high-severity issues (100 low, expected baseline) |
| `poetry run pytest` | PASS — 57/57 tests passing, including all 10 new tests |

**Architecture-constraint compliance (sprint §"Architecture constraints"):**

- No YAML logic added to `nuclei_json_converter.py`.
- No new imports from `docker/`, `infra/`.
- Runtime deps still Python 3.12 + `pyyaml` + `nuclei` binary on PATH; no new third-party deps.
- `docker/entrypoint.sh` unchanged.
- `build_normalized_document` is pure (no I/O, no env, no `datetime`); caller supplies `run_date`.

**Out-of-scope items confirmed untouched:**

- `scan_run.scan_started_at` / `scan_run.scan_completed_at` / `scan_run.scanner_version` — not added.
- Backward-compat for the bare-array shape — not added.
- Schema validation on the consumer direction — not added.
- Raw JSONL output — unchanged.
- `profiles.yaml`, `entrypoint.sh`, Terraform, `.docx` files — unchanged.

## CSFLite control validation

This change does not introduce, modify, or remove any CSFLite control IDs. Existing profile→control mappings in `scanner/profiles/profiles.yaml` (`csf_subcategory` field) remain authoritative against `csflite/controls.json`. No re-validation needed for this sprint.

## Unresolved items (honestly flagged)

1. **Manual end-to-end check pending** — sprint §Verification calls for running `scanner/scan.py <existing-client>` and inspecting the resulting `result-YYYY-MM-DD.json`. This requires Nuclei installed on the host and would scan external assets. Not run. Recommend running against `deployments/localtest` with the DVWA harness (per README §"Testing Against DVWA") so no real client targets are touched.

2. **Seed-doc not revised** — the new envelope keys (`schema_version`, `scan_run.client`, `scan_run.run_date`, `scan_run.profiles_executed`, `scan_run.findings_count`) are not yet documented in §3 "Normalized JSON Output" of `.claude/docs/LeanSecurity_Nuclei_seed_document.md`. The current §3 table is finding-level only. Sprint did not require a seed-doc delta; if the contract should be documented in the seed for future readers, a delta should be drafted (similar pattern to `seed-document-v1.2-delta.md`).

3. **CLAUDE.md line 28** — still references `claude-project/LeanSecurity_Nuclei_Seed_Document.md`. Line 20 was corrected by an intentional edit during this session; line 28 was missed. One-line fix, outside this sprint's scope — flagging for next CLAUDE.md cleanup.

4. **Working tree carries unrelated edits**: `CLAUDE.md` (intentional edits), `.claude/docs/scope.md` deletion, `.claude/sprint.md` rename/edit, `.claude/plan.md` + `.claude/scope.md` untracked. None of these are part of the scanner change set; they are loop-process artifacts and pre-existing branch state. The 4-file scanner change set listed above is the entire deliverable for this sprint.

## Recommendation for next step

Either:

- **(a)** Stage and commit the scanner change set (`scanner/*.py` + `tests/test_nuclei_json_converter.py`) as one commit, then run the manual end-to-end against `localtest`; or
- **(b)** Run the end-to-end first, fold any fixes in, then commit one cohesive change.
