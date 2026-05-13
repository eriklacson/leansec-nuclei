# README addition — Local Docker section

Merge into `README.md` immediately after the "Quick Start (Local CLI)" section
and before any test-environment / DVWA section. Keep the existing Local CLI
section unchanged.

---

## Quick Start (Local Docker)

Local Docker mode runs the same `scan.py` as Local CLI mode, inside a
container. Output is identical: same JSONL files, same normalized JSON,
same paths under `results/<client>/YYYY-MM/`. Local CLI and Local Docker
are interchangeable — downstream consumers cannot tell which produced the
output.

The local image does not include cloud CLIs. For cloud-mode automated
deployment, use the cloud Dockerfile (separate, follow-up).

### Prerequisites

- Docker Engine or Docker Desktop
- Repository cloned locally
- A populated `deployments/<client>/targets.txt`

No Nuclei install required on the host. No Python install required on the
host. The image carries everything.

### Build

From the repo root:

```bash
docker build -f docker/Dockerfile.local -t leansecurity/nuclei-scanner:local .
```

The trailing `.` is the build context (repo root). The build:

- Bakes `scanner/` and `scanner/profiles/profiles.yaml` into the image
- Pins Nuclei to the version specified by the `NUCLEI_VERSION` build arg
  (verify against [Nuclei releases](https://github.com/projectdiscovery/nuclei/releases)
  before bumping)
- Installs `pyyaml` via pip — no Poetry in the runtime image
- Does not include `gcloud`, `aws`, or `az`

To override the Nuclei version at build time:

```bash
docker build \
  --build-arg NUCLEI_VERSION=v3.4.11 \
  -f docker/Dockerfile.local \
  -t leansecurity/nuclei-scanner:local .
```

### Run

```bash
docker run --rm \
  -e CLIENT=<client> \
  -v "$(pwd)/deployments:/app/deployments:ro" \
  -v "$(pwd)/results:/app/results" \
  leansecurity/nuclei-scanner:local
```

`CLIENT` is required. `<client>` must match a directory under `deployments/`
containing a `targets.txt`. Results land on the host at
`results/<client>/YYYY-MM/`, identical in shape to Local CLI output.

### Environment variables

| Variable | Default | Purpose |
|---|---|---|
| `CLIENT` | _(required)_ | Deployment name; matches `deployments/<client>/` |
| `CLOUD_PROVIDER` | `local` | `local` for Docker mode; `gcp`/`aws`/`azure` for cloud |
| `UPDATE_TEMPLATES` | `true` | Whether to run `nuclei -update-templates` at container start |

`CONFIG_BUCKET`, `RESULTS_BUCKET`, and `TARGETS_PATH` apply only in cloud
modes (`CLOUD_PROVIDER` ≠ `local`) and are validated by the entrypoint when
required.

### Output

After a successful run, on the host:

```
results/<client>/YYYY-MM/
├── baseline_web_YYYY-MM.jsonl
├── patch_cve_YYYY-MM.jsonl
├── identity_remote_access_YYYY-MM.jsonl
├── data_protection_YYYY-MM.jsonl
├── transport_security_YYYY-MM.jsonl
├── owasp_top10_core_YYYY-MM.jsonl
├── vuln_monitoring_YYYY-MM.jsonl
└── result-YYYY-MM-DD.json
```

Seven raw JSONL files (one per profile, native Nuclei `-je` format) plus
one consolidated normalized JSON. Same files Local CLI mode produces.

### Skipping template updates

The container runs `nuclei -update-templates` at startup by default.
For air-gapped environments, fast iteration, or repeated test runs:

```bash
docker run --rm \
  -e CLIENT=<client> \
  -e UPDATE_TEMPLATES=false \
  -v "$(pwd)/deployments:/app/deployments:ro" \
  -v "$(pwd)/results:/app/results" \
  leansecurity/nuclei-scanner:local
```

### Changing scan profiles

`profiles.yaml` is baked into the image at build time. To change profiles:

1. Edit `scanner/profiles/profiles.yaml`
2. Rebuild the image (`docker build -f docker/Dockerfile.local -t leansecurity/nuclei-scanner:local .`)
3. Re-run

This matches the cloud-mode workflow, where the CI image-build pipeline
rebuilds on `scanner/profiles/**` changes. Runtime profile downloads from
configuration buckets are no longer part of the architecture
(see [ADR-007](decisions/ADR-007-python-in-container.md)).

### When to use Local Docker vs Local CLI

| Scenario | Recommendation |
|---|---|
| First-time scan during a client engagement | Local CLI — fastest iteration |
| Validating a profile change before merge | Local Docker — same image as cloud |
| Demonstrating the scanner without installing Python/Nuclei on the host | Local Docker |
| Sanity-checking before cloud cutover | Local Docker |
| CI smoke tests | Local Docker — see `tests/test_container.py` |

### Common issues

| Symptom | Likely cause |
|---|---|
| `ERROR: CLIENT environment variable is required` | `-e CLIENT=<name>` flag missing |
| `ERROR: targets file not found: /app/deployments/<client>/targets.txt` | Volume mount missing, or `<client>` directory doesn't exist under `deployments/` |
| `ERROR: Unsupported CLOUD_PROVIDER: <value>` | `CLOUD_PROVIDER` must be one of `local`, `gcp`, `aws`, `azure` |
| `docker build` fails with `COPY scanner/...: not found` | Build context is wrong — must be repo root, not `docker/`. Verify the trailing `.` in the build command. |
| Empty JSONL files for all profiles | Targets unreachable, or no findings against the target set. Validate against DVWA / Juice Shop / WebGoat for known-bad fixtures. |
| Permission denied writing to `results/` | Volume permission mismatch on Linux hosts. `mkdir -p results && chmod 777 results` for test environments; tighten for production. |

### Architecture

The container's bash entrypoint is a thin wrapper. It validates required
environment, optionally refreshes Nuclei templates, then invokes
`python -m scanner.scan ${CLIENT}` — the same code path Local CLI mode
uses. Cloud-mode storage dispatch (`download_config`, `upload_results`)
lives in the same entrypoint but only runs when `CLOUD_PROVIDER` is
non-`local`.

See [`decisions/ADR-007-python-in-container.md`](decisions/ADR-007-python-in-container.md)
for the architectural rationale (why Python carries over into the container,
why bash remains the entrypoint shell, what the v1.1 seed-document decision
this supersedes was protecting against).
