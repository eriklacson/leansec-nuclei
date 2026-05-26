# Plan — Seed Document v1.3 Consistency Cleanup

**Date:** 2026-05-26
**Branch:** `chore/claude-metadocs-cleanup`
**Single file touched:** `.claude/docs/LeanSecurity_Nuclei_seed_document.md`

> Replaces the previous `update/normalize_json_wrapper` plan, which is now merged to main.

## Open questions / assumptions

- **Assumption:** No new seed version bump (1.3 → 1.4) because this changes no contract, no design decision, and no behavior. The Change Log §12 is not extended. If the architect disagrees, bump to 1.3.1 with a "registry refresh, no contract change" entry.
- **Assumption:** Status column in §5 for the 4 newly-documented scripts is `Complete` (all four files exist and have functional implementations in the repo today).
- **Open:** Do `upload_to_gcs.py` and `validate_profiles.py` belong under §5 "Local CLI (baseline)" or under a new "Operator tools" subsection? I'll put them in **Local CLI** because they run from the same Python environment as `scan.py` and have no Docker/Terraform dependency. Architect can re-bucket on review.

## Edit-by-edit plan

All edits to `.claude/docs/LeanSecurity_Nuclei_seed_document.md`.

### Edit 1 — §1 Project Separation typos (line 26)

Replace:
> Transformation layer (conversts raw Nuclie JSONL to normalized JSON format for Conduit P2 ingest adaptor), nfrastructure modules

With:
> Transformation layer (converts raw Nuclei JSONL to normalized JSON format for Conduit P2 ingest adapter); Infrastructure modules

(Use `;` to separate the two clauses cleanly. "adaptor" → "adapter" for consistency with §1 line 25 which already uses "P2 ingest adapter".)

### Edit 2 — §4 Repository Structure tree (lines 295–343)

**Under `scanner/`** add four entries between `nuclei_helpers.py` and the `profiles/` subdir:
```
├── nuclei_json_converter.py      ← Raw-JSONL → v1 envelope transformation
├── nuclei_convert_tool.py        ← Standalone re-consolidation CLI
├── upload_to_gcs.py              ← Manual GCS push CLI (consultant workflow)
├── validate_profiles.py          ← Nuclei template-tag validator
```

**Under `tests/`** replace the single-line stub with:
```
├── tests/                            ← pytest suite (scanner layer)
│   ├── test_nuclei_helpers.py
│   ├── test_nuclei_json_converter.py
│   ├── test_container.py
│   ├── test_upload_to_gcs.py
│   └── validation/                   ← Validation fixtures
```
(`test_container.py` is already in §5 Local Docker; listing it in §4 tree completes the picture.)

**Remove** the `├── setup.sh` line entirely.

### Edit 3 — §4 Language Policy bash bullet (line 361)

Replace:
> **Bash (container entrypoint + bootstrap):** `docker/entrypoint.sh`, `setup.sh`.

With:
> **Bash (container entrypoint):** `docker/entrypoint.sh`.

### Edit 4 — §5 Local CLI Component Registry (lines 373–386)

**Remove** the `setup.sh` row.

**Add** six new rows after `tests/test_nuclei_helpers.py`:

| Component | Source/Domain | Status |
|---|---|---|
| `scanner/nuclei_json_converter.py` | Raw-JSONL → v1 envelope transformation. Hosts `SCHEMA_VERSION`, `build_normalized_document`, `list_executed_profiles`, `consolidate_jsonl_dir` | Complete |
| `scanner/nuclei_convert_tool.py` | Standalone re-consolidation CLI — rebuilds `result-YYYY-MM-DD.json` from existing JSONL without re-scanning | Complete |
| `scanner/upload_to_gcs.py` | Manual GCS push CLI — uploads `results/<client>/<YYYY-MM>/` to GCS bucket. Supports the manual-push workflow in §3 Deployment Modes | Complete |
| `scanner/validate_profiles.py` | Validates every `tags:` entry in `profiles.yaml` against the locally-installed Nuclei template library. Dev/CI tooling | Complete |
| `tests/test_nuclei_json_converter.py` | Unit tests for the v1 envelope contract | Complete |
| `tests/test_upload_to_gcs.py` | Unit tests for the GCS upload helper | Complete |

### Edit 5 — §10 Locked Design Decisions

No edit. The setup.sh policy is not a locked decision in §10, so removing the file does not change §10.

## What I will NOT touch

- §3 Interface Contracts — already correct after v1.3 fold.
- §6 Scan Profiles, §7 CSFLite Control Mapping — verified matches `profiles.yaml`.
- §10 Locked Design Decisions, §11 What This Project Does Not Own — no contract change.
- §12 Change Log — no version bump per assumption above.
- The two delta files in `.claude/docs/` — both correctly marked APPLIED, retained for history.
- Any scanner/, docker/, infra/, deployments/, tests/, .github/ file.

## Verification step (after edits)

1. Re-grep the seed for `setup.sh` → expect zero matches.
2. Re-grep the seed for `nuclei_json_converter`, `nuclei_convert_tool`, `upload_to_gcs`, `validate_profiles` → each should appear in §4 tree AND §5 registry (plus pre-existing §3 mentions for the first two).
3. Re-grep the seed for `conversts`, `Nuclie`, `nfrastructure`, `adaptor` → expect zero matches.
4. Visually skim §4 tree to confirm directory ordering still reads cleanly.
5. Diff against `main` to confirm only the seed document and the two `.claude/` metadocs changed.

## Report after implementation

Write `.claude/report-claude-metadocs-cleanup.md` per CLAUDE.md step 6, summarizing edits made, verification results, and any items flagged for follow-up.
