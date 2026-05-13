# Plan: Shared Docker network for local validation harness

Implementation plan for the scope in [`scope.md`](scope.md). Source task
spec: [`.claude/tasks.md`](../tasks.md).

## Pre-flight

- Confirm scanner image exists locally:
  `docker image inspect leansecurity/nuclei-scanner:local >/dev/null`
- Confirm Docker Compose v2 is available: `docker compose version`
- Working tree is on `fix/local-docker-validation-network`; no
  uncommitted changes under `scanner/`, `docker/`, or
  `tests/test_container.py` (these are out of scope and must remain
  untouched).

## Open questions for architect review (resolve before IMPLEMENT)

1. **README anchor mismatch.** Tasks.md says place the new subsection
   "after 'Common issues'" in "Quick Start (Local Docker)". The current
   README has no "Common issues" subsection — the Local Docker block ends
   at the "Notes:" list (README.md:70–75), then "Testing Against DVWA
   (Local)" begins at line 77. **Proposed resolution:** insert the new
   subsection at line 76 (between the Notes list and the DVWA section).

   Architect: Insert New Subsection

2. **Overlap with existing DVWA section.** README.md:77–95 already
   documents a Local-CLI DVWA workflow that conflicts conceptually with
   the new container-hostname harness. **Proposed resolution:** leave
   the existing DVWA section unchanged in this PR — it remains valid
   for Local CLI mode. Add the new subsection above it so readers find
   the Local Docker variant first when they're in the Local Docker
   context.

   Archiectect: Confirm Existing DVWA Section Remains Valid

3. **`webgoat/webgoat` image stability.** Tasks.md notes flakiness on
   ARM. **Proposed resolution:** proceed with `webgoat/webgoat`; if it
   fails to start during step 4 verification, stop and flag rather than
   silently swapping to `webgoat/goatandwolf`.

   Architect: Don't include WebGoat image swap in the PR.

## Implementation steps

### Step 1 — `deployments/_validation/targets.txt`

- Create directory `deployments/_validation/`.
- Write `targets.txt` with the three container-hostname URLs verbatim
  from tasks.md §Deliverables.1.
- No Terraform files in this directory — `_validation` is a fixture, not
  a deployable client. The underscore prefix matches the existing
  `_example/` exclusion convention.

### Step 2 — `tests/validation/docker-compose.yaml`

- Create directory `tests/validation/`.
- Write `docker-compose.yaml` verbatim from tasks.md §Deliverables.2.
- Critical invariants the file must preserve:
  - `container_name` set explicitly on each service (predictable
    hostname regardless of Compose project name).
  - `networks.scanner-validation.name: scanner-validation` (avoids
    Compose's `<projectname>_<netname>` prefix so `docker run
    --network=scanner-validation` works without computation).
  - No `ports:` mappings — scanning happens inside the network.
  - Images unpinned in this draft (pinning deferred per scope).

### Step 3 — Verify harness brings up cleanly

```bash
docker compose -f tests/validation/docker-compose.yaml config       # parses
docker compose -f tests/validation/docker-compose.yaml up -d        # starts
docker compose -f tests/validation/docker-compose.yaml ps           # all running
```

Spot-check intra-network reachability without involving the scanner:

```bash
docker run --rm --network=scanner-validation curlimages/curl \
  curl -sI -o /dev/null -w '%{http_code}\n' http://dvwa/
docker run --rm --network=scanner-validation curlimages/curl \
  curl -sI -o /dev/null -w '%{http_code}\n' http://juice-shop:3000/
docker run --rm --network=scanner-validation curlimages/curl \
  curl -sI -o /dev/null -w '%{http_code}\n' http://webgoat:8080/WebGoat/
```

Each should return a 2xx/3xx. Allow ~30s after `up -d` for Juice Shop and
WebGoat to finish booting. **If WebGoat fails, stop and flag (open
question 3).**

### Step 4 — Verify scanner produces findings > 0

```bash
docker run --rm \
  --network=scanner-validation \
  -e CLIENT=_validation \
  -v "$(pwd)/deployments:/app/deployments:ro" \
  -v "$(pwd)/results:/app/results" \
  leansecurity/nuclei-scanner:local
```

Acceptance check:

```bash
test -s results/_validation/$(date +%Y-%m)/result-$(date +%Y-%m-%d).json && \
  jq 'length' results/_validation/$(date +%Y-%m)/result-$(date +%Y-%m-%d).json
```

Findings count must be `> 0`. If 0:

1. Confirm scanner container joined the network mid-run (separate
   terminal): `docker network inspect scanner-validation`
2. Confirm templates present:
   `docker run --rm --entrypoint sh leansecurity/nuclei-scanner:local -c "ls ~/.local/nuclei-templates/ | head"`
3. Do **not** "fix" by editing scanner code — debug the harness.

Do not commit anything under `results/` (gitignored; verify with
`git status --ignored results/`).

### Step 5 — `tests/validation/README.md`

- Create from tasks.md §Deliverables.3 verbatim. Sections preserved:
  What this is / What it is not / Prerequisites / Bring up / Run scan /
  Expected output / Troubleshooting zero findings / Tear down / Why not
  `--network=host` or `host.docker.internal`.
- Confirm intra-doc bash code blocks render correctly (the tasks.md
  source uses escaped fences; emit unescaped triple-backticks in the
  final file).

### Step 6 — Root `README.md` addition

- Insert new subsection `### Validating the build against known-vulnerable apps`
  at line 76, between the existing Notes list (ends line 75) and the
  "Testing Against DVWA (Local)" header (line 77).
- Body verbatim from tasks.md §Deliverables.4 (again, unescape the
  nested code fences).
- Leave the existing "Testing Against DVWA (Local)" section unchanged
  (see open question 2).

### Step 7 — Tear down and verify clean state

```bash
docker compose -f tests/validation/docker-compose.yaml down
docker network ls | grep scanner-validation && echo FAIL || echo OK
```

The network should be removed by `down`. `OK` confirms a clean teardown.

### Step 8 — Lint and final repo hygiene

```bash
poetry run black --check .
poetry run ruff check .
poetry run python -m pytest -q --maxfail=1 --disable-warnings
```

No Python source changes are expected, but run the suite to confirm no
incidental regressions (e.g. `tests/test_container.py` still passes
unchanged).

`git status` should show only:

- `deployments/_validation/targets.txt` (new)
- `tests/validation/docker-compose.yaml` (new)
- `tests/validation/README.md` (new)
- `README.md` (modified — one subsection inserted)
- `.claude/docs/scope.md`, `.claude/docs/plan.md` (planning artifacts;
  separate commit or excluded per project convention)

Nothing under `scanner/`, `docker/`, or `tests/test_container.py`.

## Verification matrix (acceptance criteria → step)

| AC # | Acceptance criterion                                | Verified in |
|------|-----------------------------------------------------|-------------|
| 1    | `deployments/_validation/targets.txt` exists, 3 entries, container hostnames | Step 1 |
| 2    | `docker compose ... config` parses                  | Step 3      |
| 3    | `docker compose ... up -d` brings apps to running    | Step 3      |
| 4    | Scanner produces `result-YYYY-MM-DD.json` w/ findings > 0 | Step 4 |
| 5    | `tests/validation/README.md` documents end-to-end    | Step 5      |
| 6    | Root README subsection links to harness doc          | Step 6      |
| 7    | No changes under `scanner/`, `docker/`, `test_container.py` | Step 8 |

## Risks and mitigations

- **WebGoat fails to boot on ARM.** Mitigation: stop and flag; do not
  silently swap images (open question 3).
- **Scanner produces zero findings even with correct network.**
  Mitigation: troubleshooting steps in §Step 4 isolate template
  availability vs. network reachability vs. profile coverage before any
  scanner-code change is considered. Out-of-scope guard still holds.
- **README anchor drift.** Mitigation: open question 1 resolves the
  insertion point before edit; commit reviews the diff at line 76.
- **Compose network name prefix.** Mitigation: explicit `name:` field
  under the network definition (§Step 2 invariants); spot-checked in
  Step 3 via `docker network inspect scanner-validation`.

## Out-of-scope guard (re-stated)

Do not modify, even incidentally:

- `scanner/scan.py`, `scanner/nuclei_helpers.py`,
  `scanner/profiles/profiles.yaml`
- `docker/Dockerfile.local`, `docker/entrypoint.sh`
- `tests/test_container.py`

If a step appears to require touching any of these, stop and escalate —
the root cause is almost certainly in the harness, not the scanner.

## CSFLite traceability

No new control coverage. Preserves existing mappings (per `profiles.yaml`
and `csflite/controls.json`):

- `baseline_web` → PR.AA-01, PR.DS-01, PR.AA-03, PR.IR-01
- `patch_cve`, `owasp_top10_core`, `vuln_monitoring` → PR.PS-01
- `identity_remote_access` → PR.AA-01, PR.AA-03
- `data_protection` → PR.DS-01
- `transport_security` → PR.IR-01

The harness validates these profiles continue to produce findings after
a Local Docker rebuild — it does not introduce or remap controls.
