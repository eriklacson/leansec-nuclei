# Scope — Seed Document v1.3 Consistency Cleanup

**Date:** 2026-05-26
**Branch:** `chore/claude-metadocs-cleanup`
**Task type:** Documentation drift cleanup (no scanner/container/infra code changes)

> Replaces the previous `update/normalize_json_wrapper` scope, which is now merged to main.

## What I'm being asked to do

The user asked me to audit `.claude/docs/LeanSecurity_Nuclei_seed_document.md` (v1.3) against the live repo and the two applied delta files (`seed-document-v1.2-delta.md`, `seed-document-v1.3-delta.md`). I reported findings; the user said "proceed with the plan."

This is a **registry/inventory refresh** of the seed — the substantive v1.3 envelope contract is already correctly folded. Sections §4 (Repository Structure tree) and §5 (Component Registry) did not get refreshed when new scanner/test files landed across the last few sprints.

## Confirmed deltas to fix

1. **`setup.sh` references are stale.** File does not exist in the repo. Drop all three references (§4 tree, §5 registry row, §4 Language Policy bash bullet). *(Decision recorded 2026-05-26: drop, do not restore.)*

2. **Scanner files cited in §3 contracts but missing from §4 tree and §5 registry:**
   - `scanner/nuclei_json_converter.py` — owner of `build_normalized_document(...)`, `list_executed_profiles(...)`, `SCHEMA_VERSION = 1` (v1.3 envelope)
   - `scanner/nuclei_convert_tool.py` — standalone re-consolidation CLI

3. **Scanner files present but undocumented anywhere in the seed:**
   - `scanner/upload_to_gcs.py` — manual GCS push CLI (supports the §3 "manual `gcloud storage cp`" workflow)
   - `scanner/validate_profiles.py` — Nuclei template-tag validator
   *(Decision recorded 2026-05-26: add both as operator tools.)*

4. **Test files present but missing from §4 tree / §5 registry:**
   - `tests/test_nuclei_json_converter.py` — covers v1.3 envelope contract
   - `tests/test_upload_to_gcs.py` — covers upload helper
   - `tests/validation/` — validation fixtures directory
   - (`tests/test_container.py` is already in §5 under Local Docker — correct.)

5. **§1 Project Separation typos in the Nuclei row (line 26):**
   - `conversts` → `converts`
   - `Nuclie` → `Nuclei`
   - `nfrastructure` → `Infrastructure`
   - Parenthesis mismatch — close after "ingest adapter" properly.
   - Normalize `adaptor` → `adapter` for internal consistency with line 25.

## Explicitly out of scope

- No changes to `scan.py`, `nuclei_helpers.py`, `nuclei_json_converter.py`, `entrypoint.sh`, Dockerfiles, Terraform, or profiles.yaml.
- No restoration of `setup.sh` (user chose drop).
- No changes to §3 envelope contract — it's already correct.
- No new ADR — this is documentation refresh, not an architectural decision.
- No version bump on the seed (no contract change; only registry refresh).
- The extra `deployments/_validation/` directory is consistent with the `_*` rule in §4 and needs no doc change.

## Acceptance criteria

1. `setup.sh` no longer mentioned anywhere in the seed.
2. §4 tree under `scanner/` lists all 6 Python files (`scan.py`, `nuclei_helpers.py`, `nuclei_json_converter.py`, `nuclei_convert_tool.py`, `upload_to_gcs.py`, `validate_profiles.py`) plus `profiles/profiles.yaml`.
3. §4 tree under `tests/` lists all 4 test files plus `validation/`.
4. §5 Local CLI registry contains rows for the 4 newly-documented scripts and 2 newly-documented test files, each with a one-line purpose and `Complete` status.
5. §1 Project Separation Nuclei row reads cleanly with no typos.
6. No regression: previously-correct §3 contract details, §6 profile table, §7 control mapping, §10 design decisions, §12 change log all unchanged.
