# Report — Seed Document v1.3 Consistency Cleanup

**Date:** 2026-05-26
**Branch:** `chore/claude-metadocs-cleanup`
**Scope:** `.claude/scope.md` | **Plan:** `.claude/plan.md`

## What I changed

Single file edited: `.claude/docs/LeanSecurity_Nuclei_seed_document.md`. Net diff: +19 / -7 lines.

| # | Location | Change |
|---|---|---|
| 1 | §1 Project Separation, Governance Pipeline row (L25) | `adaptor` → `adapter` (internal consistency) |
| 2 | §1 Project Separation, Nuclei row (L26) | `conversts` → `converts`; `Nuclie` → `Nuclei`; `nfrastructure` → `Infrastructure`; closed parenthesis cleanly |
| 3 | §2 Runtime Language Policy bullet (L41) | Dropped `setup.sh` from the bootstrap/dev-tooling bullet (kept pre-commit hooks) |
| 4 | §4 Repository Structure tree (`scanner/`) | Added 4 entries: `nuclei_json_converter.py`, `nuclei_convert_tool.py`, `upload_to_gcs.py`, `validate_profiles.py` |
| 5 | §4 Repository Structure tree (`tests/`) | Expanded from 1-file stub to 4 files + `validation/` subdir |
| 6 | §4 Repository Structure tree (root) | Removed `setup.sh` line |
| 7 | §4 Language Policy bash bullet | `docker/entrypoint.sh, setup.sh` → `docker/entrypoint.sh` |
| 8 | §5 Local CLI Component Registry | Removed `setup.sh` row; added 6 new rows (4 scripts + 2 test files), each `Complete` |

## What I did NOT change (per plan)

- §3 Interface Contracts — already correct after v1.3 fold
- §6 Scan Profiles / §7 CSFLite mapping — verified consistent with `profiles.yaml`
- §10 Locked Design Decisions / §11 What This Project Does Not Own
- §12 Change Log — no version bump (no contract change, registry refresh only)
- The two `.claude/docs/seed-document-v1.x-delta.md` files — correctly marked APPLIED, retained for history
- Any scanner/, docker/, infra/, deployments/, tests/, .github/, or CLAUDE.md content

## Verification results

Per the plan's verification step:

| Check | Expected | Actual |
|---|---|---|
| `grep -n "setup\.sh" <seed>` | 0 hits | 0 hits ✓ |
| `grep -nwE "conversts\|Nuclie\|adaptor" <seed>` | 0 hits | 0 hits ✓ |
| `grep -nE "nfrastructure[^_]" <seed>` (excluding `infrastructure` false positives) | 0 hits | 0 hits ✓ |
| `nuclei_json_converter` in §4 tree AND §5 registry | both | ✓ (L300, L384) |
| `nuclei_convert_tool` in §4 tree AND §5 registry | both | ✓ (L301, L385) |
| `upload_to_gcs` in §4 tree AND §5 registry | both | ✓ (L302, L386) |
| `validate_profiles` in §4 tree AND §5 registry | both | ✓ (L303, L387) |
| `test_nuclei_json_converter`, `test_upload_to_gcs` in §4 + §5 | both | ✓ (L337/L390, L339/L391) |
| Only seed + `.claude/` metadocs changed | true | ✓ (no scanner/docker/infra/tests/deployments touched) |

## Acceptance criteria (from scope)

| # | Criterion | Status |
|---|---|---|
| 1 | `setup.sh` not mentioned anywhere in the seed | ✓ |
| 2 | §4 tree lists all 6 scanner Python files + profiles.yaml | ✓ |
| 3 | §4 tree lists all 4 test files + `validation/` | ✓ |
| 4 | §5 Local CLI registry contains rows for 4 scripts + 2 test files | ✓ |
| 5 | §1 Project Separation Nuclei row reads cleanly with no typos | ✓ |
| 6 | No regression in §3 / §6 / §7 / §10 / §12 | ✓ |

## Items flagged for follow-up (not fixed in this task)

None blocking. Two optional polish items the architect may want to consider:

1. **Should `upload_to_gcs.py` and `validate_profiles.py` get their own §3 interface-contract subsections?** Currently they are listed in §5 with one-line descriptions, but unlike `scan.py` / `nuclei_helpers.py` / `nuclei_json_converter.py`, they have no formal contract entry. The seed-doc convention is fuzzy here — `scan.py` is the only CLI with a full contract table. Recommend deferring until a consumer actually integrates against these CLIs.

2. **§5 has no row for the `deployments/_validation/` directory.** It is consistent with the §4 boundary rule that `_*` dirs are excluded from deploys, but if it has a documented purpose (e.g., used by `tests/validation/`), one line in §5 or §4 could help. Did not touch in this task because the user only asked to align the seed to existing references, not to add new docs.

## Honest unresolved items

None.
