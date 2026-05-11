# Task: Shared Docker network for local validation harness

## Context

The Local Docker scanner (`docker/Dockerfile.local`, built per ADR-007) produces
zero findings when targeting the local validation harness (DVWA, OWASP Juice
Shop, WebGoat). Local CLI mode against the same targets produces findings as
expected.

Root cause: network namespace mismatch. The validation apps run as containers
exposed on the host's loopback (`127.0.0.1:8001-8003` for the prior setup, or
`127.0.0.1:80` for DVWA). When the scanner runs as a container, `127.0.0.1`
inside the scanner container points at *its own* loopback — not the host's,
and not the validation apps. Nothing is reachable; Nuclei completes with zero
findings; `scan.py` consolidates empty JSONL files and exits cleanly.

This is a Docker networking property, not a defect in `scan.py` or
`entrypoint.sh`. The fix is in the test harness setup, not the scanner code.

**Do not modify** `scanner/scan.py`, `scanner/nuclei_helpers.py`,
`scanner/profiles/profiles.yaml`, `docker/Dockerfile.local`, or
`docker/entrypoint.sh`. The scanner is correct as-is.

## Decision

Use Option C from the architect review: shared Docker network. The scanner
container and the validation apps join a named Docker network and address
each other by container name. This avoids `--network=host` (Linux-only,
defeats isolation, doesn't work on Docker Desktop) and avoids
`host.docker.internal` (requires per-platform target file variants).

Trade-off accepted: `targets.txt` for the validation harness uses container
hostnames (`http://dvwa:80`), which differs from what a host-based Local CLI
run would use (`http://127.0.0.1:80`). This is acceptable because:

1. The validation harness is internal tooling, not client-facing
2. Real client `targets.txt` files use external hostnames/IPs that resolve
   identically from both host and container — mode parity holds for real
   engagements
3. The scanner output contract (filenames, paths, normalized JSON shape)
   remains identical between Local CLI and Local Docker

## In scope

- New `deployments/_validation/` directory with a `targets.txt` using
  container hostnames for DVWA, Juice Shop, WebGoat
- New `tests/validation/docker-compose.yaml` defining the validation harness
  (DVWA, Juice Shop, WebGoat) on a shared network named `scanner-validation`
- New `tests/validation/README.md` documenting the validation harness
  workflow end-to-end
- README addition under the existing "Quick Start (Local Docker)" section
  pointing readers at the validation harness for sanity checks

## Out of scope

- Any change to `scanner/`, `docker/Dockerfile.local`, or `docker/entrypoint.sh`
- Any change to `profiles.yaml`
- `tests/test_container.py` modifications — that file's existing fixtures
  use ephemeral tmp_path mounts and unreachable targets by design, and
  should not be re-pointed at the validation harness
- Anything cloud-related
- Live client deployments

## Deliverables

### 1. `deployments/_validation/targets.txt`

Plain text. One URL per line. Container hostnames, not `127.0.0.1`.

```
# Validation harness targets — for use with tests/validation/docker-compose.yaml
# Scanner must run on the scanner-validation Docker network to resolve these.
http://dvwa:80
http://juice-shop:3000
http://webgoat:8080
```

The directory name is `_validation` with a leading underscore — this matches
the existing convention for `deployments/_example/` and ensures it is
excluded from any CI/CD that filters out underscore-prefixed deployment
folders. It is a validation fixture, not a live client.

### 2. `tests/validation/docker-compose.yaml`

Defines the three validation apps and the shared network. Apps are named
exactly as the `targets.txt` hostnames expect.

```yaml
# Local validation harness for the scanner container.
#
# Brings up DVWA, OWASP Juice Shop, and WebGoat on a shared Docker network
# named scanner-validation. The scanner container joins this network at
# run time (see tests/validation/README.md) and addresses each app by
# container hostname.
#
# Usage:
#   docker compose -f tests/validation/docker-compose.yaml up -d
#   # ... run the scanner ...
#   docker compose -f tests/validation/docker-compose.yaml down

services:
  dvwa:
    image: vulnerables/web-dvwa
    container_name: dvwa
    networks:
      - scanner-validation
    restart: unless-stopped

  juice-shop:
    image: bkimminich/juice-shop
    container_name: juice-shop
    networks:
      - scanner-validation
    restart: unless-stopped

  webgoat:
    image: webgoat/webgoat
    container_name: webgoat
    networks:
      - scanner-validation
    restart: unless-stopped

networks:
  scanner-validation:
    name: scanner-validation
    driver: bridge
```

Notes for implementation:

- `container_name` is set explicitly on each service so the scanner can
  address them by predictable hostname regardless of Compose project name.
- `networks.scanner-validation.name: scanner-validation` forces the network
  name to `scanner-validation` rather than `<projectname>_scanner-validation`
  — the scanner's `docker run --network=scanner-validation` invocation
  must work without computing a Compose-derived prefix.
- No host port mappings. The whole point is that scanning happens inside
  the network; the host doesn't need to reach the apps. If a developer
  wants to also load DVWA in a browser for manual exploration, they can
  add `ports:` locally without committing that change.
- Image versions are left unpinned in this initial draft. If the architect
  wants reproducibility, pin each image to a specific digest in a follow-up.

### 3. `tests/validation/README.md`

Document the full validation workflow. Suggested structure:

```markdown
# Scanner validation harness

Local validation for the scanner container. Confirms that a rebuilt image
produces findings against known-vulnerable web apps.

## What this is

A `docker-compose.yaml` that brings up three intentionally-vulnerable web
apps (DVWA, OWASP Juice Shop, WebGoat) on a shared Docker network. The
scanner container joins the same network at run time and scans them by
container hostname.

This is NOT a CI test. It's a manual sanity check after rebuilding the
scanner image, and a reference setup for consultants validating profile
changes.

## What it is not

- It is not a security assessment of the apps.
- It is not a benchmark of detection quality.
- It is not a substitute for `tests/test_container.py` (which validates
  container plumbing, not scan content).
- It is not how real client scans work. Real clients have external
  targets reachable from any network.

## Prerequisites

- Docker Engine or Docker Desktop with Compose v2
- The scanner image built locally:
  `docker build -f docker/Dockerfile.local -t leansecurity/nuclei-scanner:local .`
- Disk space for three vulnerable-app images (~2GB total)

## Bring up the harness

From the repo root:

\`\`\`bash
docker compose -f tests/validation/docker-compose.yaml up -d
\`\`\`

Wait ~30 seconds for the apps to initialize, especially Juice Shop and
WebGoat. Verify the apps are healthy:

\`\`\`bash
docker compose -f tests/validation/docker-compose.yaml ps
\`\`\`

All three should show `running` (or `healthy` if healthchecks are added
later).

## Run a scan against the harness

\`\`\`bash
docker run --rm \\
  --network=scanner-validation \\
  -e CLIENT=_validation \\
  -v "$(pwd)/deployments:/app/deployments:ro" \\
  -v "$(pwd)/results:/app/results" \\
  leansecurity/nuclei-scanner:local
\`\`\`

Key points:

- `--network=scanner-validation` puts the scanner on the same network as
  the harness apps. Without this flag, the scanner cannot resolve `dvwa`,
  `juice-shop`, or `webgoat` and will produce zero findings.
- `CLIENT=_validation` matches the directory under `deployments/`. The
  `targets.txt` in that directory uses container hostnames.
- Results land at `results/_validation/YYYY-MM/` on the host, same layout
  as any other client.

## Expected output

After a successful run, expect findings > 0 across multiple profiles. The
three apps are intentionally vulnerable; `baseline_web` and
`owasp_top10_core` should reliably surface findings. `vuln_monitoring`
and `patch_cve` may or may not depending on Nuclei template coverage at
the time of the scan.

If you see zero findings:

1. Confirm the harness apps are running: `docker compose -f tests/validation/docker-compose.yaml ps`
2. Confirm the scanner joined the correct network. From a separate
   terminal, while the scan is running:
   `docker network inspect scanner-validation | grep -A2 Containers`
   The scanner container and the three apps should all be listed.
3. Confirm Nuclei templates are present inside the image:
   `docker run --rm --entrypoint sh leansecurity/nuclei-scanner:local -c "ls ~/.local/nuclei-templates/ 2>/dev/null | head"`
   If empty, the in-container template update is failing — investigate
   network egress from the container.

## Tear down the harness

\`\`\`bash
docker compose -f tests/validation/docker-compose.yaml down
\`\`\`

Add `--volumes` if you want to wipe any harness state (none is currently
persisted, but the flag is safe to use).

## Why not `--network=host` or `host.docker.internal`?

Three reasons:

1. `--network=host` is Linux-only. Docker Desktop on Mac/Windows silently
   ignores it, which would produce inconsistent behavior across team
   members' workstations.
2. `host.docker.internal` requires changing `targets.txt` to a
   Docker-specific hostname, which would break Local CLI mode against
   the same target file. Mode parity for the target file is worth
   preserving.
3. The shared-network approach matches how real production scanners are
   often deployed alongside the systems they scan, and exercises Nuclei's
   ability to resolve and reach targets by hostname rather than IP — a
   slightly more realistic test surface.
\`\`\`

### 4. README addition

In the project root `README.md`, in the "Quick Start (Local Docker)" section
(after "Common issues"), add a short subsection pointing at the validation
harness. Suggested wording:

\`\`\`markdown
### Validating the build against known-vulnerable apps

After rebuilding the scanner image, you can sanity-check it against a
local validation harness (DVWA, Juice Shop, WebGoat). See
[`tests/validation/README.md`](tests/validation/README.md) for the full
workflow. Quick version:

\`\`\`bash
# Bring up the harness
docker compose -f tests/validation/docker-compose.yaml up -d

# Scan it
docker run --rm \\
  --network=scanner-validation \\
  -e CLIENT=_validation \\
  -v "$(pwd)/deployments:/app/deployments:ro" \\
  -v "$(pwd)/results:/app/results" \\
  leansecurity/nuclei-scanner:local

# Tear down
docker compose -f tests/validation/docker-compose.yaml down
\`\`\`

Expect findings > 0 across multiple profiles. Zero findings against the
validation harness means something is wrong with the rebuild — the apps
are intentionally vulnerable.
\`\`\`

## Acceptance criteria

1. `deployments/_validation/targets.txt` exists with three entries
   (`dvwa`, `juice-shop`, `webgoat`) using container hostnames
2. `tests/validation/docker-compose.yaml` exists; `docker compose -f
   tests/validation/docker-compose.yaml config` parses without errors
3. `docker compose -f tests/validation/docker-compose.yaml up -d`
   brings the three apps to running state
4. After the harness is up, running the scanner with
   `--network=scanner-validation -e CLIENT=_validation` produces a
   `result-YYYY-MM-DD.json` with findings count > 0 under
   `results/_validation/YYYY-MM/`
5. `tests/validation/README.md` exists and documents bring-up, scan, and
   tear-down end to end
6. Root `README.md` has a subsection in "Quick Start (Local Docker)"
   linking to `tests/validation/README.md`
7. No files under `scanner/`, `docker/`, or `tests/test_container.py`
   are modified

## Implementation order

1. Create `deployments/_validation/targets.txt`
2. Create `tests/validation/docker-compose.yaml`
3. Verify `docker compose ... up -d` succeeds and the three apps are
   reachable from inside the network (use `docker run --rm
   --network=scanner-validation alpine/curl curl -sI http://dvwa/` as a
   spot check)
4. Verify the scanner produces findings > 0 against the harness
5. Create `tests/validation/README.md`
6. Update root `README.md`
7. Run `docker compose ... down`; verify the network is cleaned up
8. Open PR; merge gates on a manual validation run by the architect

## Notes for the implementing agent

- This task does not require any Python code changes. If you find
  yourself editing files under `scanner/` or `docker/`, stop and re-read
  the "out of scope" section.
- The scanner image must already exist locally before testing; assume
  the architect has run the Dockerfile.local build before invoking you.
- Do not pin the validation app images to specific versions in this
  initial draft. The architect will pin in a follow-up if reproducibility
  becomes an issue for the harness.
- If the `webgoat/webgoat` image fails to start in your environment
  (it's been historically flaky on ARM hosts), flag this in the PR
  description and propose `webgoat/goatandwolf` as a substitute — do
  not silently swap.
- Do not commit anything to `results/` — that directory is gitignored
  and validation output should never enter version control.