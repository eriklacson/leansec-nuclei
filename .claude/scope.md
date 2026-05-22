## Scope — Normalized JSON Wrapper (sprint `update/normalize_json_wrapper`)

### What we're building

Introduce a v1 envelope around `result-YYYY-MM-DD.json` so external consumers (third-party SLO trackers, dashboards, future Conduit P2 ingest) integrate against a stable, evolvable contract. The bare-array shape currently emitted by `consolidate_jsonl_dir` is retired entirely — no backward-compat mode.

Target shape (sprint §"Reference: target shape"):

```json
{
  "schema_version": 1,
  "scan_run": {
    "client": "<client>",
    "run_date": "YYYY-MM-DD",
    "profiles_executed": ["<sorted profile names>"],
    "findings_count": <int>
  },
  "findings": [ <unchanged finding objects> ]
}
```

Finding object shape is unchanged; only the outer container changes.

### Why

- Seed doc §3 ("Normalized JSON Output") defines the consumed contract for the SLO tracking component; it currently produces a bare list, which is brittle for evolving consumers.
- Establishes `schema_version` as the evolution lever (e.g., future `scan_started_at`, `scanner_version` are explicitly out of scope for this iteration — sprint §"Out of scope").

### Where the work lands

Scanner layer only. Per sprint §"Architecture constraints" and ADR-007 boundary rules:

- `scanner/nuclei_json_converter.py` — add `SCHEMA_VERSION = 1`, `build_normalized_document(...)`, `list_executed_profiles(directory)`; broaden module docstring.
- `scanner/scan.py` — rename local `consolidated` → `findings`; call `list_executed_profiles` + `build_normalized_document`; write the wrapper instead of the bare array; extend the existing import from `nuclei_json_converter`.
- `scanner/nuclei_convert_tool.py` — same wrapper logic for the standalone re-consolidation CLI; update end-of-run summary.
- `tests/test_nuclei_json_converter.py` — keep existing finding-level tests; add 9 new unit tests + 1 round-trip integration test (sprint §Task 5–6).

No changes to: `docker/entrypoint.sh`, `profiles.yaml`, Terraform, `nuclei_helpers.py` (YAML stays exclusive to it), raw JSONL output, or `.docx` quickstart/implementation guides.

### Constraints to honor

- Runtime deps stay Python 3.12 + `pyyaml` + `nuclei` on PATH. No new third-party deps.
- `build_normalized_document` must be pure (no I/O, no `datetime`, no env). Caller passes `run_date`.
- `profiles_executed` is sorted in both helpers (deterministic output).
- Strip `_YYYY-MM` suffix via regex (`r"_\d{4}-\d{2}$"`), not a hardcoded literal; non-matching `.jsonl` filenames keep their bare stem rather than crashing.
- `list_executed_profiles` raises `NotADirectoryError` if the path is not a directory.

### CSFLite linkage

The wrapper does not change which controls profiles produce evidence for. Existing profile→control mappings (`profiles.yaml` `csf_subcategory`) remain authoritative per `csflite/controls.json`. Wrapper introduces no new control claim.

### Architecture references

- **ADR-007** (in `decisions/`): reaffirms scanner-layer boundaries — `scanner/` does not import from `docker/` or `infra/`. The wrapper change respects this; output stays identical between local CLI and container modes (same `scan.py` runs in both).
- **Seed doc §3 "Interface Contracts"**: lists the Normalized JSON Output field mapping. This sprint formalizes the *envelope*; finding-level fields are already in the contract.
- **Seed doc §12 Change Log**: v1.2 (May 2026) is the current published rev; this wrapper work is incremental on top of v1.2 and does not require a seed-doc revision (no decision reversal, no boundary change).

### Verification gate (sprint §Verification)

`black --check`, `ruff check`, `bandit -r . --severity-level high`, `pytest` — all four must pass. Then a manual end-to-end check: run `scanner/scan.py <existing-client>` and confirm the top-level keys, `schema_version == 1` (int), and `findings_count == len(findings)` on the resulting `result-YYYY-MM-DD.json`.

### Discrepancies surfaced during READ

- **CLAUDE.md path drift**: CLAUDE.md references `claude-project/LeanSecurity_Nuclei_Seed_Document.md`, but the seed doc actually lives at `.claude/docs/LeanSecurity_Nuclei_seed_document.md`. Worth a follow-up update to CLAUDE.md (not in scope for this sprint).
- **Seed-doc delta already applied**: `.claude/docs/seed-document-v1.2-delta.md` notes it was folded into the seed doc on 2026-05-07 and should not be re-applied — confirmed against §10 and §12 in the seed.

### Open questions

None — sprint spec is explicit on all knobs (schema version literal, sort order, purity, error behavior, out-of-scope items). If ambiguity arises, sprint §"Out of scope" instructs to stop and ask.
