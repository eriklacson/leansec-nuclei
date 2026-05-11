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

```bash
docker compose -f tests/validation/docker-compose.yaml up -d
```

Wait ~30 seconds for the apps to initialize, especially Juice Shop and
WebGoat. Verify the apps are healthy:

```bash
docker compose -f tests/validation/docker-compose.yaml ps
```

All three should show `running` (or `healthy` if healthchecks are added
later).

## Run a scan against the harness

```bash
docker run --rm \
  --network=scanner-validation \
  -e CLIENT=_validation \
  -v "$(pwd)/deployments:/app/deployments:ro" \
  -v "$(pwd)/results:/app/results" \
  leansecurity/nuclei-scanner:local
```

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

```bash
docker compose -f tests/validation/docker-compose.yaml down
```

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
