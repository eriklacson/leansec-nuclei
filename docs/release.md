# Releasing the Scanner Image to GHCR

Maintainer-side procedure for publishing the `leansecurity-nuclei` scanner image to GitHub Container Registry. **Audience: maintainers** with push access to the public repository. End users consuming the image should read [`setup-guide.md`](setup-guide.md) instead.

The publish pipeline is defined in [`.github/workflows/publish-image.yaml`](../.github/workflows/publish-image.yaml). The tag scheme and triggers are described in [`gcp_architecture.md`](gcp_architecture.md#5-public-repo-cicd-model) — this document covers the operational procedure, not the design.

---

## One-time GHCR setup

Do these once per repository / organization. Skip if already done.

### 1. Confirm GitHub Actions can write to packages

Repository settings → **Actions → General → Workflow permissions**:

- Set to **"Read and write permissions"**.

The workflow also declares `permissions: packages: write` explicitly, but the org-level default must allow it.

### 2. First publish creates a private package

The first successful run of `publish-image.yaml` creates `ghcr.io/eriklacson/leansec-nuclei` as a **private** package by default. End users (Cloud Run jobs in client GCP projects) cannot pull a private package without auth.

Flip it to public:

1. Visit the package page: `https://github.com/users/eriklacson/packages/container/package/leansec-nuclei`.
2. **Package settings** (right-hand sidebar) → scroll to **Danger Zone** → **Change visibility** → **Public**.
3. Confirm by typing the package name.

### 3. Link the package to the source repository

On a personal account the package is **auto-linked to its source repository** (`eriklacson/leansec-nuclei`) on first publish, so no manual step is required here. If the package was ever published from a different repo and lost its link, re-link it on the package settings page:

- **Manage Actions access** → add `eriklacson/leansec-nuclei` with the **Write** role. This lets future workflow runs from the source repo update the package.

### 4. Verify

```bash
# As an anonymous user (no docker login):
docker pull ghcr.io/eriklacson/leansec-nuclei:latest
```

Should succeed with no auth prompt. If it asks for credentials, the package is still private.

---

## Updating the image as you go

Most maintainer work is iterative: bump a dependency, add a profile, tweak the entrypoint, ship. The publish workflow handles this loop automatically — you do not cut a tag for every change.

### What triggers a new publish

The workflow's path filter is the contract:

| Path you changed | New image published? |
|------------------|----------------------|
| `docker/**` (Dockerfile, entrypoint.sh, .dockerignore) | yes |
| `scanner/**` (scan.py, profiles.yaml, helpers, tests) | yes |
| `infra/**`, `docs/**`, `deployments/**`, `README.md` | no |
| `.github/workflows/publish-image.yaml` itself | no — bump via `workflow_dispatch` or an empty `docker/` touch if you need to validate the workflow change |

The path filter is intentional. Terraform-only or doc-only PRs don't burn a build slot or move `:latest` for no reason.

### The iteration loop

```bash
# Branch, change, push, PR.
git checkout -b feature/bump-nuclei
$EDITOR docker/Dockerfile.local        # e.g. bump NUCLEI_VERSION
git add docker/Dockerfile.local
git commit -m "bump nuclei to vX.Y.Z"
git push -u origin feature/bump-nuclei
# Open PR. ci.yaml runs lint + tests on the PR.
# Merge to main. publish-image.yaml fires automatically.
```

After merge, the workflow publishes two tags onto the same image:

- `:latest` — moves to the new build.
- `:sha-<short>` — immutable; matches the merge commit's short SHA.

### Testing a mid-flight build against the validation harness

Before deciding the build is good enough to promote to a semver tag, pull the new `:sha-<short>` and scan the validation harness ([`tests/validation/README.md`](../tests/validation/README.md)):

```bash
# Find the short SHA from the Actions run, or:
SHA=$(git rev-parse --short HEAD)

docker pull ghcr.io/eriklacson/leansec-nuclei:sha-${SHA}

docker compose -f tests/validation/docker-compose.yaml up -d

docker run --rm \
  --network=scanner-validation \
  -e CLIENT=_validation \
  -v "$(pwd)/deployments:/app/deployments:ro" \
  -v "$(pwd)/results:/app/results" \
  ghcr.io/eriklacson/leansec-nuclei:sha-${SHA}

# Expect findings > 0 across multiple profiles. Zero findings means the
# new image regressed something — investigate before promoting.

docker compose -f tests/validation/docker-compose.yaml down
```

The same image tag also lets you point a private deployment's `terraform.tfvars` at `sha-${SHA}` and apply against a test GCP project, exercising the cloud path before locking in a semver tag.

### Common change types

| Change | What to edit | Notes |
|--------|--------------|-------|
| Bump Nuclei binary | `docker/Dockerfile.local` — `NUCLEI_VERSION` build arg default | Test against validation harness; check findings count doesn't regress. |
| Add or modify a scan profile | `scanner/profiles/profiles.yaml` | The profile key becomes a JSONL filename stem; keep it stable once published. |
| Update Python dependencies | `pyproject.toml` + run `poetry lock` | Commit both. CI re-resolves and runs pytest. |
| Tweak entrypoint behavior | `docker/entrypoint.sh` | `shellcheck` is part of local verification; run it before pushing. |
| Update scanner logic | `scanner/scan.py`, `scanner/nuclei_helpers.py`, etc. | Cover changes with tests in `tests/`; CI gates on pytest. |

### When to promote `:sha-<short>` to a semver tag

After validating a `:sha-<short>` build is healthy, promote by tagging the same commit:

```bash
git checkout main && git pull --ff-only
git tag -a v1.2.3 -m "release v1.2.3"
git push origin v1.2.3
```

The workflow rebuilds from that commit and publishes `:v1.2.3` (alongside another `:sha-<short>` that matches the existing one — bit-identical, since the source is the same). Pin client deployments to the semver tag, not the SHA, so the human-readable name moves through normal release coordination.

Do not retroactively tag a commit that has since been superseded by a follow-up `docker/`/`scanner/` change on main, unless you genuinely want the older snapshot in production — `:latest` will still point at HEAD, but `:v1.2.3` will lock to the older commit.

---

## Semver versioning policy

When you cut a semver tag (procedure in [Updating the image as you go](#when-to-promote-sha-short-to-a-semver-tag) above), the choice of major/minor/patch follows the **consumer contract** — what the Cloud Run container expects from its environment — not internal Python or Terraform changes:

| Bump | Trigger |
|------|---------|
| **MAJOR** | Breaking change to the env vars `entrypoint.sh` consumes (`CLOUD_PROVIDER`, `CONFIG_BUCKET`, `RESULTS_BUCKET`, `CLIENT`, etc.), or to the output JSONL filename convention. Clients pinned to the previous major will break on apply. |
| **MINOR** | New env vars with safe defaults, new profiles in `profiles.yaml`, new output files alongside existing ones. |
| **PATCH** | Bug fixes, Nuclei binary version bumps via `NUCLEI_VERSION`, dependency updates, template refresh changes. |

If a release contains both breaking + non-breaking changes, bump major.

---

## Manual trigger (workflow_dispatch)

Useful when a previous run failed for a transient reason (registry hiccup, runner timeout) and you want to re-publish without an empty commit.

1. Repository → **Actions** tab → **Publish Scanner Image** (left sidebar).
2. **Run workflow** dropdown (right side) → branch: `main` → **Run workflow**.

This produces the same `:latest` and `:sha-<short>` tags a main-branch push would, against the current `main` HEAD. It does **not** produce a semver tag — only a `git tag v*` push does that.

---

## Verifying a publish

After the Actions run goes green:

```bash
# Check the package page in a browser:
#   https://github.com/users/eriklacson/packages/container/package/leansec-nuclei
# Look for the new tag in the version list.

# Or pull anonymously to confirm visibility + content:
docker pull ghcr.io/eriklacson/leansec-nuclei:v1.2.3
docker run --rm ghcr.io/eriklacson/leansec-nuclei:v1.2.3 nuclei -version
```

`nuclei -version` exits 0 with the pinned `NUCLEI_VERSION` from the Dockerfile. If the image pulls but the version string is wrong, the build picked up a stale Nuclei binary — investigate before announcing the release.

---

## Announcing a release

The `infra/gcp/_example/main.tf` uses a relative module source (`../../infra/gcp`), so it always reflects the current checkout — no ref to bump. Consumer-side `terraform.tfvars` pin the scanner image tag. When you publish a new semver:

1. Communicate the new tag and changelog out-of-band to known consumers. There is no auto-notification mechanism — clients bump their `scanner_image` tag in `terraform.tfvars` when ready.
2. Update the default `scanner_image` in `infra/gcp/variables.tf` and in `.claude/skills/gcp-deploy/SKILL.md` (`DEFAULT_SCANNER_IMAGE`) to the new semver.

---

## Rolling back / yanking a bad release

GHCR allows deleting individual package versions:

- Package page → **Manage versions** → select the tag → **Delete**.

**Caveat:** any client whose `terraform.tfvars` is pinned to the deleted tag will fail on the next `terraform apply` (image pull error). Coordinate before deleting:

1. Confirm no production deployment is pinned to the tag.
2. If deletion is unavoidable, publish a follow-up patch (e.g. `v1.2.4`) before yanking `v1.2.3`, and notify consumers to bump their pin.

If the bad release is `:latest`, fix-forward by merging a corrected change to `main` rather than deleting — `:latest` is mutable by design and will move on the next push.

---

## See also

- [`gcp_architecture.md` §5](gcp_architecture.md#5-public-repo-cicd-model) — design and trigger rationale.
- [`.github/workflows/publish-image.yaml`](../.github/workflows/publish-image.yaml) — workflow source.
- [`setup-guide.md`](setup-guide.md) — consumer-side perspective.
