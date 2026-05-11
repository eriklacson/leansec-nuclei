# Scope: Shared Docker network for local validation harness

## Problem

Local Docker scanner produces zero findings against the local validation
harness (DVWA, Juice Shop, WebGoat) because `127.0.0.1` inside the scanner
container resolves to the container's own loopback, not the host's. Local
CLI mode against the same targets works correctly.

This is a Docker networking property, not a scanner defect. The fix
belongs in the test harness setup.

## Approach

Shared Docker network (Option C from architect review). The scanner
container and validation apps join a named Docker network
(`scanner-validation`) and address each other by container hostname.

Rejected alternatives:
- `--network=host` — Linux-only, silently ignored on Docker Desktop
- `host.docker.internal` — requires per-platform `targets.txt` variants,
  breaks mode parity with Local CLI

## In scope

- `deployments/_validation/targets.txt` — container-hostname targets for
  DVWA, Juice Shop, WebGoat
- `tests/validation/docker-compose.yaml` — three vulnerable apps on the
  `scanner-validation` shared network, predictable container names, no
  host port mappings, unpinned images (initial draft)
- `tests/validation/README.md` — full bring-up, scan, tear-down workflow;
  rationale for shared-network approach; troubleshooting for zero-finding
  runs
- Root `README.md` — short subsection under "Quick Start (Local Docker)"
  linking to the validation harness doc

## Out of scope

- Any change to `scanner/scan.py`, `scanner/nuclei_helpers.py`,
  `scanner/profiles/profiles.yaml`
- Any change to `docker/Dockerfile.local` or `docker/entrypoint.sh`
- `tests/test_container.py` — its ephemeral tmp_path + unreachable-target
  fixtures are intentional and must not be re-pointed at the harness
- Cloud deployments and live client deployments
- Pinning validation app images to digests (deferred follow-up)
- CI integration of the harness — this is a manual sanity check, not a
  CI test

## Trade-off accepted

`targets.txt` for the validation harness uses container hostnames
(`http://dvwa:80`), which differs from a host-based Local CLI run
(`http://127.0.0.1:80`). Acceptable because:

1. The validation harness is internal tooling, not client-facing
2. Real client `targets.txt` files use external hostnames/IPs that
   resolve identically from host and container — mode parity holds for
   real engagements
3. Scanner output contract (filenames, paths, normalized JSON shape)
   remains identical between Local CLI and Local Docker

## Acceptance criteria

1. `deployments/_validation/targets.txt` exists with three
   container-hostname entries
2. `docker compose -f tests/validation/docker-compose.yaml config`
   parses without errors
3. `docker compose -f tests/validation/docker-compose.yaml up -d` brings
   the three apps to running state
4. Scanner run with `--network=scanner-validation -e CLIENT=_validation`
   produces `result-YYYY-MM-DD.json` with findings > 0 under
   `results/_validation/YYYY-MM/`
5. `tests/validation/README.md` documents bring-up, scan, tear-down end
   to end
6. Root `README.md` has a subsection in "Quick Start (Local Docker)"
   linking to `tests/validation/README.md`
7. No files under `scanner/`, `docker/`, or `tests/test_container.py` are
   modified

## CSFLite alignment

No new CSFLite control coverage. This work preserves existing coverage
(baseline_web → PR.AA-01, PR.DS-01, PR.AA-03, PR.IR-01; owasp_top10_core,
patch_cve, vuln_monitoring → PR.PS-01) by ensuring the Local Docker mode
can be validated against known-vulnerable targets before client use.
