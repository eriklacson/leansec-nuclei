# ADR-008: Per-client private repo as a second deployment topology

- **Status:** Accepted
- **Date:** 2026-07-02
- **Supersedes (partially):** Seed document §"Client Deployments" — prior wording (before this ADR's accompanying doc edit) read: "The client's deployment lives under `deployments/<client>/` in the repository. The client does not own or modify the scanner, infrastructure modules, or CI/CD workflows." That line was rewritten to describe both topologies as part of the same commit that adds this ADR (`LeanSecurity_Nuclei_seed_document.md:17`); see "What this supersedes" below for the before/after.
- **Related:** Task spec `.claude/tasks/gha-config-sync-private-repo.md`; the `gcp-deploy` skill (`.claude/skills/gcp-deploy/`), which implements the in-repo topology this ADR does not replace; `infra/gcp/client-repo-template/README.md`, the operator-facing walkthrough for the topology this ADR describes.
- **Architect:** Erik
- **Consulted:** —

## Context

The seed document locks a single deployment topology: a client's config
(`targets.txt`, `profiles.yaml`, Terraform inputs) lives in `deployments/<client>/`
inside this repository, is gitignored, and is never pushed anywhere the client can see
or touch. The `gcp-deploy` skill (merged, PR #16) was built against exactly this model —
it resolves the Terraform module by a relative path (`../../infra/gcp`) that only
resolves from inside a checkout of this repo, and assumes the operator (the architect)
runs every `terraform apply` locally.

Task `gha-config-sync-private-repo.md` asks for a second topology: a client gets a
dedicated GitHub repository holding their `deployment.yaml`, `targets.txt`,
`profiles.yaml`, and GitHub Actions workflows that run `terraform apply` and sync config
to GCS on every push to `main`. This is not achievable inside the existing model — an
external repo has no relative path to this repo's `infra/gcp` module, and "GHA in the
client's repo drives redeployments" is a direct contradiction of "the client does not own
or modify... CI/CD workflows."

Resolved with the architect (2026-07-02): the per-client repo is **client-owned**, not a
repo the architect creates or holds write access to. The client forks or copies
`infra/gcp/client-repo-template/` into their own GitHub account, receives WIF trust
values from the architect after a one-time local bootstrap, and operates their own repo
independently — including pushing config changes and merging PRs that trigger their own
deployments — from that point on.

## Decision

Two deployment topologies now coexist for the GCP cloud tier, chosen per client:

1. **In-repo (existing, default, unchanged).** `deployments/<client>/` inside this repo,
   gitignored, architect-operated via the `gcp-deploy` skill. Module resolved by relative
   path. No client access to this repo. Documented in the seed document and
   `docs/setup-guide.md`.

2. **Client-owned repo (new, this ADR).** A private repo the **client** creates in
   **their own** GitHub account, scaffolded from `infra/gcp/client-repo-template/`
   (git-ref-pinned module source, since no relative path is possible from an external
   repo). GitHub Actions in the client's repo — authenticated via Workload Identity
   Federation only, no long-lived service account keys — runs `terraform plan` on PR and
   `terraform apply` + GCS config sync on merge to `main`. The client operates this repo
   independently after a one-time architect-run local bootstrap that provisions the WIF
   trust binding (`infra/gcp/main.tf`'s `enable_wif` / `wif_github_repository`, already
   present in the module) scoped to the client's repo.

Topology 2 requires the client repo to exist **before** the architect's local bootstrap
apply, because `wif_github_repository` is that repo's `owner/repo` name and must be known
to create the WIF trust binding. Sequence: client creates repo → architect runs local
bootstrap with WIF enabled and the client's repo name → architect hands the client the
WIF provider/SA values via the `gcp-deploy` skill's Step 11 → client scaffolds and pushes
the template.

Neither topology is deprecated. The architect chooses per client based on how much
operational independence that client needs.

## What this supersedes — explicitly

| Seed doc (superseded, in part) | This ADR |
|---|---|
| "The client's deployment lives under `deployments/<client>/` in the repository." | True for the in-repo topology only. A client on the second topology has their own repo instead. |
| "The client does not own or modify the scanner, infrastructure modules, or CI/CD workflows." | Still true for the scanner and `infra/gcp/` module (consumed by version-pinned reference, never forked or edited). **No longer true for CI/CD workflows** on the client-owned topology: the client's repo has its own `deploy.yml`/`plan.yml`, which the client can read, and which runs on their own merges. |

The seed document's one-sentence description of client deployments should be updated to
name both topologies; that line-level doc edit ships alongside this ADR.

## What this preserves — explicitly

- **The `infra/gcp` Terraform module is not forked or modified.** Both topologies consume
  it as-is — one by relative path, one by pinned git ref. Module changes still happen in
  exactly one place.
- **No long-lived credentials leave GCP.** Topology 2 uses WIF exclusively, matching how
  the module already supports external CI (`enable_wif`, added before this ADR).
- **The architect still gates the first apply.** WIF trust for a client repo cannot exist
  until the architect runs a local bootstrap and explicitly enables it — a client cannot
  self-provision trust into a GCP project they don't already have IAM on.
- **`scanner/`, `docker/`, `ci.yaml`, `publish-image.yaml` are unaffected.** This ADR is
  scoped to the GCP deployment/config-sync path only.

## Consequences

### Positive

- Clients who want to self-manage their own scan targets and redeploy cadence can, without
  the architect being a bottleneck for every `targets.txt` edit.
- WIF-only auth means no service account JSON key ever exists outside GCP, even in a repo
  the architect does not control.

### Negative / risk

- **The architect loses direct visibility into a client-owned repo's history and content**
  once handed off — unlike the in-repo topology, there's no way to audit what a client
  pushes without being added as a collaborator. This is an accepted tradeoff of "client
  owns and operates their own repo," not something this ADR mitigates.
- **Two `main.tf`/template styles now exist** in this repo (`infra/gcp/_example/`, relative
  path, in-repo topology vs. `infra/gcp/client-repo-template/`, git-ref, client-owned
  topology). Docs must keep these clearly distinguished or operators will copy the wrong
  one into the wrong context.
- **WIF trust is scoped to whatever `owner/repo` the architect was given at bootstrap
  time.** If a client transfers or renames their repo, the WIF binding breaks silently
  until the architect re-runs bootstrap with the new name — no automated reconciliation
  exists.

## Corrections (2026-08-13)

A static review after this ADR merged (`.claude/report-gha-topology-doc-review.md`,
`.claude/tasks/client-repo-topology-gaps.md`) found the topology described above **could
not actually run**. Fixed on `component/gcp-update-via-actions`; corrections below, not a
new decision.

- **The WIF binding described in "Decision" (item 2, `enable_wif` / `wif_github_repository`)
  bound the *scanner* service account**, not a distinct CI identity. The scanner SA's
  complete grant set was two bucket bindings (`objectViewer` on the config bucket,
  `objectAdmin` on results) — no project-level roles, no state-bucket access. Every step of
  `deploy.yml`/`plan.yml` (`terraform init`, `terraform apply`) failed on first run.
  **Fixed:** `enable_wif` now provisions a dedicated `deployer` service account, separate
  from the scanner SA, with the seven project-level roles CI actually needs
  (`run.admin`, `iam.serviceAccountAdmin`, `iam.serviceAccountUser`, `storage.admin`,
  `cloudscheduler.admin`, `iam.workloadIdentityPoolAdmin`, `artifactregistry.admin`). The
  WIF trust binding now targets this deployer SA. See `infra/gcp/README.md#enable_wif`.
- **`infra/gcp/client-repo-template/main.tf` pinned `?ref=v1.2.3`, a tag that never
  existed** in this repo — `terraform init` failed with an invalid-ref error before
  reaching anything else. **Fixed:** two-tag release. `v1.1.0` tags the commit containing
  the deployer-SA fix above; the template's `?ref=` was updated to point at it and that
  commit tagged `v1.1.1`. Clients copy the template from `v1.1.1`.
- **The "GCS config sync... on merge to `main`" step named in "Decision" (item 2) was a
  no-op re-upload**, not the mechanism by which config reached GCS. The module already
  manages `targets.txt`/`profiles.yaml` as Terraform-managed bucket objects; the preceding
  `terraform apply` in the same workflow run had already uploaded both. The sync step was a
  second, redundant writer to a Terraform-managed resource. **Fixed:** removed from
  `deploy.yml`. Config reaches GCS through `terraform apply` alone, on both topologies.
- **`region`, `enable_scheduler`, `enable_ar_mirror`, `schedule_cron`, and
  `schedule_timezone` were not plumbed as passthrough variables** between the architect's
  bootstrap module invocation and the client template's module invocation — two separate
  Terraform roots writing the same remote state. Any of these left at the client template's
  default silently reverted it on the client's first CI apply. `enable_ar_mirror` reverting
  is destructive: it deletes the Artifact Registry mirror and every image in it. **Fixed:**
  all five are now required variables (no default) on the client template, matching what
  the architect's bootstrap apply actually used — an unset value fails `terraform plan`
  instead of silently reverting on `terraform apply`.

None of the above changes the decision itself — both topologies still coexist, the module
is still consumed by relative path or pinned ref without forking, and WIF is still the only
auth mechanism for topology 2. This section corrects what "Decision" claimed the mechanism
already did, which turned out not to be true until this fix pass.
