# Plan — Fix GHCR namespace (`leansecurity` → `eriklacson`)

Companion to `.claude/report.md` (investigation, 2026-06-03). Resolves the "package cannot
be found" failure: GHCR packages live under the **repo owner's** namespace, and the repo is
owned by the personal account `eriklacson` (`git@github.com:eriklacson/leansec-nuclei.git`),
so `GITHUB_TOKEN` cannot push to `ghcr.io/leansecurity/*`.

## Decision (confirmed by architect, 2026-06-03)

- **Ship under `eriklacson`.** Reverts the rename in commit `ab0d275`. No GitHub-org work.
- Workflow `IMAGE_NAME` set to the **explicit literal** `eriklacson/leansec-nuclei`
  (architect chose explicit over `${{ github.repository }}`). A one-line note on the
  `github.repository` alternative is kept in the migration section for the future-org case.
- Three distinct "not found" defects are fixed in one pass:
  1. **GHCR image namespace** — `ghcr.io/leansecurity/leansec-nuclei` → `ghcr.io/eriklacson/leansec-nuclei`.
  2. **Terraform module source repo** — `github.com/leansecurity/leansecurity-nuclei` (doubled name, non-existent) → `github.com/eriklacson/leansec-nuclei`.
  3. **Package-page URLs** — `github.com/orgs/leansecurity/.../nuclei-scanner` → `github.com/users/eriklacson/packages/container/package/leansec-nuclei` (also fixes pre-rename `nuclei-scanner` → `leansec-nuclei`).

## Scope boundary — what is NOT a namespace problem

These strings contain `leansecurity` but are **not** the GHCR owner; they do not affect package
resolution. Default: **leave them** (project brand name is still "Lean Security"). Renaming is a
separate cosmetic decision (Phase 3), not required for the fix.

- Project-name prose `leansecurity-nuclei` (README.md:143, docs/*, deployments/_example/README.md:10).
- State-bucket suffix `*-tfstate-leansecurity-nuclei` (backend.tf:6, setup-guide.md:39/47/48/93, bootstrap script).
- Local-only build tags `leansecurity/leansec-nuclei:local` / `:test-local` — never pushed to GHCR.

---

## Sequencing

Strict gate order: **Phase 1 (operative) → Phase 2 (docs) → Phase 3 (cosmetic, optional) →
Phase 4 (manual GitHub, architect)**. Phase 1 alone makes the package publishable; Phases 2–3
are consistency. Phase 4 cannot be done from the repo and is the architect's.

---

## Phase 1 — Operative changes (required for the package to exist & be pullable)

| # | File | Line | Current | Change to |
|---|---|---|---|---|
| 1.1 | `.github/workflows/publish-image.yaml` | 18 | `IMAGE_NAME: leansecurity/leansec-nuclei` | `IMAGE_NAME: eriklacson/leansec-nuclei` |
| 1.2 | `infra/gcp/variables.tf` | 16 | `default = "ghcr.io/leansecurity/leansec-nuclei:latest"` | `...eriklacson/leansec-nuclei:latest` |
| 1.3 | `deployments/_example/terraform.tfvars` | 4 | `scanner_image = "ghcr.io/leansecurity/leansec-nuclei:v1.0.0"` | `...eriklacson/...:v1.0.0` |
| 1.4 | `deployments/_example/main.tf` | 9 | `source = "git::https://github.com/leansecurity/leansecurity-nuclei.git//infra/gcp?ref=v1.0.0"` | `...github.com/eriklacson/leansec-nuclei.git//infra/gcp?ref=v1.0.0` |
| 1.5 | `deployments/_example/main.tf` | 44 | `default = "ghcr.io/leansecurity/leansec-nuclei:v1.0.0"` | `...eriklacson/...:v1.0.0` |
| 1.6 | `scripts/bootstrap-gcp-client.sh` | 140 | `scanner_image = "ghcr.io/leansecurity/leansec-nuclei:vX.Y.Z"` | `...eriklacson/...:vX.Y.Z` |

**Watchpoint (1.4):** the module `source` pins `?ref=v1.0.0`. Fixing the URL only helps if a
`v1.0.0` git tag actually exists on `eriklacson/leansec-nuclei`. If it does not, `terraform init`
still fails — just with a different error. Flag in report; confirm tag exists or adjust the ref.

**Verify Phase 1:**
- `grep -rn "leansecurity/leansec-nuclei\|leansecurity-nuclei.git" <Phase-1 files>` → zero hits.
- `terraform fmt -check` + `terraform validate` in `infra/gcp/` pass.
- `actionlint .github/workflows/publish-image.yaml` passes.
- `shellcheck scripts/bootstrap-gcp-client.sh` passes.
- Copy `deployments/_example/` to `/tmp`, dummy-substitute placeholders, `terraform init -backend=false` reaches module download without the "repository not found" error (or fails only on the `v1.0.0` ref watchpoint above).

---

## Phase 2 — Documentation consistency (image namespace + package URLs)

Only the **GHCR image references** and **package-page URLs** change here — not project-name prose.

### 2a. `ghcr.io/leansecurity/leansec-nuclei` → `ghcr.io/eriklacson/leansec-nuclei`

| File | Lines |
|---|---|
| `README.md` | 19, 52, 59, 88, 136 |
| `docs/release.md` | 23, 41, 91, 100, 171, 172 |
| `docs/gcp_architecture.md` | 27, 38, 138, 139, 140 |
| `docs/setup-guide.md` | 76, 264, 352 |
| `infra/gcp/README.md` | 31, 69 |

Note: README.md:52/59/88 are local `docker build/run -t` tags. Strictly Phase-3 cosmetic, but
they sit in the same code blocks as the pull URLs — change them together to avoid a mixed-namespace
README. (Their `tests/`/`CLAUDE.md` siblings remain Phase 3.)

### 2b. Module source URL in docs

| File | Line | Change |
|---|---|---|
| `infra/gcp/README.md` | 65 | `github.com/leansecurity/leansecurity-nuclei.git//infra/gcp...` → `github.com/eriklacson/leansec-nuclei.git//infra/gcp...` |

### 2c. Package-page URLs + Actions-access slug + stale `nuclei-scanner` (release.md)

| File | Line | Current | Change to |
|---|---|---|---|
| `docs/release.md` | 23 | "creates `ghcr.io/leansecurity/leansec-nuclei`" | `...eriklacson/...` |
| `docs/release.md` | 27 | `https://github.com/orgs/leansecurity/packages/container/package/nuclei-scanner` | `https://github.com/users/eriklacson/packages/container/package/leansec-nuclei` |
| `docs/release.md` | 35 | "add `leansecurity/leansecurity-nuclei` with the Write role" | drop or → `eriklacson/leansec-nuclei` (personal-account packages auto-link to the source repo, so the manual Actions-access step is unnecessary; reword to say so) |
| `docs/release.md` | 167 | `# https://github.com/orgs/leansecurity/packages/container/package/nuclei-scanner` | `# https://github.com/users/eriklacson/packages/container/package/leansec-nuclei` |

**Verify Phase 2:**
- `grep -rn "ghcr.io/leansecurity\|orgs/leansecurity\|leansecurity-nuclei.git\|nuclei-scanner" README.md docs/ infra/gcp/README.md` → zero hits.
- Manual cross-link audit: README ↔ setup-guide ↔ gcp_architecture ↔ infra/gcp/README links still resolve.
- No mixed-namespace code block remains in README.md.

---

## Phase 3 — Cosmetic / optional (no effect on package resolution)

Architect decision pending — **default is to leave these.** Listed so nothing is silently missed.

- Local build tags `leansecurity/leansec-nuclei:local` / `:test-local` → `eriklacson/...`:
  `CLAUDE.md` 81/88/96/101, `tests/validation/README.md` 30/59/88, `tests/test_container.py:20`.
  (Arbitrary local tags; renaming only buys cosmetic consistency. If renamed, re-run
  `pytest tests/test_container.py` since the image tag constant changes.)
- Project-name prose `leansecurity-nuclei` and state-bucket suffix `*-tfstate-leansecurity-nuclei`
  (`README.md:143`, `docs/release.md:3`, `docs/gcp_architecture.md:3/7`, `docs/setup-guide.md`
  3/20/39/47/48/93, `deployments/_example/README.md:10`, `deployments/_example/backend.tf:6`,
  `scripts/bootstrap-gcp-client.sh` 3/15/35/44/62). Brand string, not a namespace — recommend keep.
- `report-gcp-cloud-deploy.md` 13/52 — historical sprint report; leave as-is.

---

## Phase 4 — Manual GitHub steps (architect-only; cannot be done from the repo)

1. **Confirm whether the publish job ran on the merge.** The trigger fires only on `main`/`v*`
   pushes touching `docker/**` or `scanner/**` (`publish-image.yaml:7-13`). The `component/gcp-deploy`
   merge was mostly `infra/**`, `docs/**`, `deployments/**`, `.github/**` — likely excluded.
   Check **Actions → Publish Scanner Image**:
   - *No run* → path filter skipped it; trigger via **Run workflow** (`workflow_dispatch` is wired) after Phase 1 merges.
   - *Run exists but red* → the `denied` push from the wrong namespace (now fixed).
2. **Trigger a publish** after the namespace fix lands: either a commit touching `docker/**` or
   `scanner/**`, or **Run workflow**.
3. First successful push creates `ghcr.io/eriklacson/leansec-nuclei` as a **private** package.
4. **Make it public:** `https://github.com/users/eriklacson/packages/container/package/leansec-nuclei`
   → Package settings → Danger Zone → Change visibility → Public.
5. **Verify anonymously:** `docker pull ghcr.io/eriklacson/leansec-nuclei:latest` (no auth prompt).

---

## Migration note (future `leansecurity` org)

If the org is created and the repo transferred later, the reverse rename applies, **plus**: the
GHCR package must be transferred/recreated under the org, and consumers' `scanner_image` pins +
module `source` refs bumped. Setting `IMAGE_NAME: ${{ github.repository }}` instead of the literal
would make the *workflow* side automatic across that transfer — kept as an option, not chosen now.

---

## Verification matrix

| Gate | Command | Phase |
|---|---|---|
| Namespace residue (operative) | `grep -rn "ghcr.io/leansecurity\|leansecurity-nuclei.git" <Phase-1 files>` → 0 | 1 |
| Terraform | `terraform fmt -check` + `terraform validate` in `infra/gcp/` | 1 |
| Workflow | `actionlint .github/workflows/publish-image.yaml` | 1 |
| Bash | `shellcheck scripts/bootstrap-gcp-client.sh` | 1 |
| Example module resolves | copy `_example/` → dummy-sub → `terraform init -backend=false` | 1 |
| Doc residue | `grep -rn "ghcr.io/leansecurity\|orgs/leansecurity\|nuclei-scanner" README.md docs/ infra/gcp/README.md` → 0 | 2 |
| Cross-links | manual audit | 2 |
| Python regression | `poetry run black --check . && poetry run ruff check . && poetry run pytest` | 1–3 |

**Architect-only gates (not runnable by Claude Code):** Phase 4 entirely — workflow run, package
visibility flip, anonymous `docker pull`, and confirming the `v1.0.0` git tag exists for the
module `?ref=` pin.

---

## Risks and watchpoints

1. **`?ref=v1.0.0` module pin (1.4).** Fixing the repo URL is necessary but not sufficient — the
   `v1.0.0` tag must exist on `eriklacson/leansec-nuclei`, or `terraform init` still fails. Confirm.
2. **Path-filter publish trigger.** Even after the namespace fix, the package won't appear until a
   `docker/**`/`scanner/**` change or a manual `workflow_dispatch` run (Phase 4 step 2).
3. **Mixed-namespace README.** README pull URLs (2a) and local build tags (Phase 3) live in the
   same fenced blocks — split across phases they'd leave one block half-renamed. Phase 2a pulls the
   in-README local tags forward to keep each block internally consistent.
4. **Reverting a fresh commit.** This undoes `ab0d275`; if a `leansecurity` org is genuinely
   planned soon, the architect may instead prefer the "make it real" path — confirmed not chosen.

---

## Deliverable checklist

- **Phase 1 (6 edits):** workflow IMAGE_NAME · variables.tf default · terraform.tfvars · main.tf source · main.tf default · bootstrap script.
- **Phase 2 (4 groups):** GHCR pull URLs across 5 files · module source in infra README · 4 package-URL/slug fixes in release.md · in-README local tags.
- **Phase 3 (optional):** local build tags · project-name/bucket prose — default leave.
- **Phase 4 (architect):** confirm/trigger workflow · publish · make public · verify anonymous pull.
- **Report:** `report-ghcr-namespace-fix.md` — verification results, the `v1.0.0` tag watchpoint, and the Phase-4 items still outstanding.
