# Scope — move-profiles-to-deploy

Source: `.claude/tasks/move-profiles-to-deploy-tasks.md`, task spec inline.

## Objective

Enable per-client scan profile customization by making `profiles.yaml` a per-deployment artifact
rather than a single global file. Each client's deployment directory (`deployments/<client>/`)
should contain its own `profiles.yaml` so different clients can run different profile subsets,
rate limits, or severity filters without modifying the canonical global file.

## What changes

- `scan.py`: resolve `PROFILES_PATH` from `deployments/<client>/profiles.yaml` first; fall back
  to `scanner/profiles/profiles.yaml` when absent. Current hardcoded path is replaced with a
  client-aware lookup.
- `scanner/_example/`: add `profiles.yaml` (copy of the canonical 7-profile set) so operators
  have a ready template when onboarding a new client.
- Tests: add coverage for the per-client lookup path (found vs. not found) and fallback behavior.

## What does NOT change

- `scanner/profiles/profiles.yaml` — preserved as-is. It is the global default, the Docker
  build source (`COPY scanner/ /app/scanner/`), and the GCP Terraform variable
  default (`scanner/profiles/profiles.yaml`). Removing it would break the container image and
  GCP infra without a separate ADR.
- `validate_profiles.py` — it already accepts an arbitrary `--profiles-file` flag; no change.
- All Docker and Terraform files — profiles.yaml baking into the image remains ADR-007 behavior.
- `nuclei_helpers.py` — `load_profiles(path)` already accepts an arbitrary path string; no change.

## Constraints

- `deployments/` is fully gitignored. The template copy goes in `scanner/_example/`, not
  in any client deployment directory. Clients configure their own after onboarding.
- Seed document § architecture: local CLI, local Docker, and GCP modes are independent.
  This change affects the local CLI path only (`scan.py`); Docker and GCP continue to read
  the baked-in or GCS-uploaded copy from `scanner/profiles/`.
- No new third-party dependencies.
- All CI gates must pass (`black`, `ruff`, `bandit`, `pytest`).

## Open question flagged for architect

The fallback behavior (per-client → global default) is not explicitly stated in the task.
The task says "moved" which implies removal of the global copy. But removing it would break
Docker builds and GCP infra (separate concerns from this task). Recommendation: keep the
global copy, make per-client override opt-in. Confirm before implementing.
