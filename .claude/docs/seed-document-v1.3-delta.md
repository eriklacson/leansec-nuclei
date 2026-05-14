# Seed Document Revision — v1.2 → v1.3 (delta)

> **APPLIED 2026-05-14** — folded into `LeanSecurity_Nuclei_seed_document.md`
> as part of the `update/normalize_json_wrapper` sprint. This file is retained
> for historical reference; do not apply again.

The following changes apply to the seed document when integrating the v1
normalized-JSON envelope (sprint `update/normalize_json_wrapper`). This file
is a delta, not a replacement; apply each section in place.

---

## §3 Interface Contracts — Normalized JSON Output

### Replace the existing "Normalized JSON Output — Normalized Scan Results" subsection wholesale.

#### v1.2 wording (current, before this revision)

> Produced by scan.py. Consolidated of JSONL output of Nuclei scan findings
> in `results/`. One normalized JSON object per line per finding. Identical
> format regardless of deployment mode. Consumed by SLO tracking component
> (for later development). Sample normalized JSON:
> `claude-project/normalized_sample.json`
>
> | Field | Type | Description |
> |---|---|---|
> | `timestamp` | `string` | ISO 8601 scan timestamp. |
> | `host` | `string` | Maps to host in Raw JSON Output. |
> | `template-id` | `string` | Maps to template-id' in Raw JSON Output. |
> | `info.name` | `string` | Maps to info.name in Raw JSON Output. |
> | `matched-at` | `string` | Maps to matched-at in Raw JSON Output. |
> | `info.severity` | `string` | Maps to info.severity in Raw JSON Output. |
> | `description` | `string` | Maps to description in Raw JSON Output. |

The v1.2 wording is factually wrong on two counts even before the envelope
change:

1. It described the output as "one normalized JSON object per line per
   finding" — the file has always been a single JSON document (previously a
   bare array), not JSONL.
2. The sample path was `claude-project/normalized_sample.json`; the file
   actually lives at `.claude/docs/normalized_sample.json`.

Both are corrected in the v1.3 wording.

#### v1.3 wording (this revision)

> Produced by `scan.py` (and by the standalone
> `scanner/nuclei_convert_tool.py` re-consolidation CLI). Consolidates the
> raw Nuclei JSONL output in `results/<client>/<YYYY-MM>/` into a single
> JSON document written to
> `results/<client>/<YYYY-MM>/result-<YYYY-MM-DD>.json`. Identical format
> regardless of deployment mode. Consumed by external integrations
> (third-party SLO trackers, dashboards, future Conduit P2 ingest). Sample
> normalized JSON: `.claude/docs/normalized_sample.json`.
>
> The document is wrapped in a versioned envelope so consumers integrate
> against a stable, evolvable contract. The envelope replaces the previous
> bare-array shape — there is no backward-compatibility mode.
>
> **Envelope shape:**
>
> ```json
> {
>   "schema_version": 1,
>   "scan_run": {
>     "client": "<client>",
>     "run_date": "YYYY-MM-DD",
>     "profiles_executed": ["<sorted profile names>"],
>     "findings_count": 42
>   },
>   "findings": [ <normalized finding objects> ]
> }
> ```
>
> Top-level fields and `scan_run` fields are tabled in the seed doc. The
> finding object shape is unchanged from the pre-envelope contract — only
> the outer container changed. Envelope construction is implemented in
> `scanner/nuclei_json_converter.build_normalized_document(...)`, which is
> pure (no I/O, no `datetime`, no env access); callers supply `run_date`.

---

## §12 Change Log — new entry

| Version | Date | Change |
|---|---|---|
| 1.3 | 2026-05-14 | Normalized JSON Output wrapped in a versioned envelope (sprint `update/normalize_json_wrapper`). §3 §"Normalized JSON Output" rewritten: the consolidated `result-YYYY-MM-DD.json` is now a single JSON document with `schema_version` (integer; sourced from `nuclei_json_converter.SCHEMA_VERSION = 1`), `scan_run.{client, run_date, profiles_executed, findings_count}`, and `findings[]`. The previous bare-array shape is retired with no backward-compat mode. Finding object shape is unchanged. Envelope construction lives in `scanner/nuclei_json_converter.build_normalized_document(...)`; profile-name derivation from JSONL filenames lives in `list_executed_profiles(...)`. Both `scanner/scan.py` and `scanner/nuclei_convert_tool.py` emit the envelope. Out of scope (deferred): `scan_started_at` / `scan_completed_at` / `scanner_version` fields, consumer-direction schema validation. |

---

## Sample artifact — replace `.claude/docs/normalized_sample.json`

The v1.2 sample (a bare array of two findings) is retired. Replace with an
envelope-shaped sample that demonstrates the v1 contract. The finding
objects inside the envelope are unchanged from the v1.2 sample.

---

## Out of scope for this revision

Deferred to a future v1.x revision:

- `scan_run.scan_started_at` / `scan_run.scan_completed_at` timestamps
- `scan_run.scanner_version`
- Backward-compatibility mode for reading the old bare-array shape
- Schema validation in the consumer direction
- Any changes to raw JSONL output
- Any changes to `profiles.yaml`, `entrypoint.sh`, or Terraform modules
