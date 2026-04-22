# Plan: Python Replacement for scan.sh

**Date:** 2026-04-22  
**Branch:** component/local  
**Status:** Awaiting architect approval

---

## Objective

Create `scanner/scan.py` as a Python drop-in replacement for `scanner/scan.sh`. The Python script must produce identical behavior and output structure. It reuses the existing `scanner/nuclei_helpers.py` for command building and execution, and reads `scanner/profiles/profiles.yaml` dynamically rather than hardcoding profile flags.

---

## What Changes

| File | Action | Reason |
|---|---|---|
| `scanner/scan.py` | Create | Python entry point replacing scan.sh |
| `pyproject.toml` | Add `pyyaml` runtime dep | `nuclei_helpers.py` imports `yaml`; currently undeclared |

`scan.sh` is **not deleted or modified** — it remains as the authoritative baseline. `scan.py` is a parallel implementation on the same layer.

---

## Behavioral Parity with scan.sh

| Behavior | scan.sh | scan.py plan |
|---|---|---|
| Argument | `$1` positional client name | `argparse` positional `client` |
| Nuclei not found | `exit 1` with install hint | `sys.exit(1)` with same message |
| Targets missing | `exit 1` | `sys.exit(1)` with same message |
| Template update | `nuclei -update-templates -silent` | `subprocess.run` same flags, `check=False` |
| Profile execution | 7 hardcoded `nuclei` invocations | Loop over `profiles.yaml` via `load_profiles` + `get_profile`; build command via `build_nuclei_cmd` |
| Profile failure | `\|\| true` (continue) | `except (CalledProcessError, RuntimeError): pass` |
| `-silent` flag | Added per invocation | Appended to cmd after `build_nuclei_cmd` (helper does not add it) |
| `-omit-raw` flag | Not present in scan.sh | **Removed** — `build_nuclei_cmd` adds it by default; need to match scan.sh behavior exactly |
| Output filename | `{stem}_{YYYY-MM}.jsonl` | `Path(profile["output"]).stem + f"_{scan_date}.jsonl"` |
| Output directory | `results/<client>/YYYY-MM/` | Same — passed as `scan_directory` to `_resolve_output_path` |
| Progress display | `[1/7] baseline_web` | Same format, profile count from yaml |
| Summary | Client, results path, finding count, `ls -la` equivalent, GCS push hint | Same fields; Python `glob` + line count for findings |

**Note on `-omit-raw`:** `build_nuclei_cmd` appends `-omit-raw` before `-je`. This flag is absent from `scan.sh`. To maintain exact parity the plan accepts this difference — `-omit-raw` strips raw HTTP data from JSONL findings, which is safe and desirable for Conduit ingestion. If exact parity is required, a `strip_omit_raw=False` kwarg approach is an option (not planned here unless architect directs it).

---

## File Layout

```
scanner/
├── scan.sh          ← unchanged
├── scan.py          ← new (this plan)
├── nuclei_helpers.py ← reused as-is
├── assess_helpers.py ← unchanged
├── nuclei_scan_tool.py ← unchanged
└── profiles/
    └── profiles.yaml ← read at runtime (no hardcoding)
```

---

## Implementation Sketch

```python
#!/usr/bin/env python3
"""Python replacement for scan.sh — see scanner/profiles/profiles.yaml for profile definitions."""

import argparse, shutil, subprocess, sys
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from nuclei_helpers import build_nuclei_cmd, load_profiles, run_nuclei

REPO_ROOT = Path(__file__).resolve().parent.parent
PROFILES_PATH = Path(__file__).resolve().parent / "profiles" / "profiles.yaml"


def main():
    parser = argparse.ArgumentParser(description="LeanSecurity Nuclei Local Scanner")
    parser.add_argument("client", help="client name (matches deployments/<client>/)")
    client = parser.parse_args().client
    scan_date = datetime.now().strftime("%Y-%m")

    # validate
    if not shutil.which("nuclei"):
        sys.exit("Error: nuclei is not installed.\nInstall: brew install nuclei (macOS) or go install ...")

    targets = REPO_ROOT / "deployments" / client / "targets.txt"
    if not targets.exists():
        sys.exit(f"Error: deployments/{client}/targets.txt not found")

    out_dir = REPO_ROOT / "results" / client / scan_date
    out_dir.mkdir(parents=True, exist_ok=True)

    # update templates
    print("Updating Nuclei templates...")
    subprocess.run(["nuclei", "-update-templates", "-silent"], check=False)  # noqa: S603

    profiles = load_profiles(str(PROFILES_PATH)).get("profiles", {})
    total = len(profiles)
    print(f"Starting scan for {client}...\n")

    for i, (name, profile) in enumerate(profiles.items(), 1):
        print(f"[{i}/{total}] {name}")
        stem = Path(profile.get("output", f"{name}.jsonl")).stem
        output_filename = f"{stem}_{scan_date}.jsonl"
        try:
            cmd = build_nuclei_cmd(profile, str(targets), output_path=output_filename, scan_directory=str(out_dir))
            cmd.append("-silent")
            run_nuclei(cmd)
        except Exception:
            pass  # mirror || true — continue remaining profiles on failure

    # summary
    jsonl_files = sorted(out_dir.glob("*.jsonl"))
    findings = sum(sum(1 for ln in f.open() if ln.strip()) for f in jsonl_files)
    print(f"\n─── Scan Complete ───")
    print(f"Client:  {client}\nResults: results/{client}/{scan_date}/\n")
    print(f"Total findings: {findings}\n")
    for f in jsonl_files:
        print(f"  {f}")
    print(f"\nTo push results to GCS for Conduit:")
    print(f"  gcloud storage cp {out_dir}/*.jsonl gs://<bucket>/nuclei/{scan_date}/")
```

---

## pyproject.toml Change

Add `pyyaml` as a runtime dependency (not dev-only) since `nuclei_helpers.py` is production code:

```toml
[tool.poetry.dependencies]
python = "^3.12"
pyyaml = "^6.0"
```

---

## Out of Scope

- Tests for `scan.py` — scan.sh has no tests either; adding them is a separate task
- Deleting or superseding `scan.sh` — architect decides
- Parallelising profiles — scan.sh is sequential; matching behavior
- Docker or cloud entrypoint changes — out of scope for this component

---

## Questions for Architect

1. **`-omit-raw` flag**: Accept the difference (cleaner output) or strip it from `build_nuclei_cmd` output to match scan.sh exactly?
2. **pyyaml dep**: Add to `[tool.poetry.dependencies]` (runtime) or `[tool.poetry.group.dev.dependencies]` (dev only)? Since `scan.py` is production code, runtime seems correct.
3. **scan.sh retention**: Should `scan.sh` be kept as the canonical entrypoint and `scan.py` be an alternative, or should `scan.py` become the primary?
