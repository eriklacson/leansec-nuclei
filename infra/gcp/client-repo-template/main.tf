# Client-owned deployment repo — see ADR-008 in the leansec-nuclei repo
# (decisions/ADR-008-per-client-repo-topology.md) for why this topology
# exists and how it differs from the in-repo deployments/<client>/ model.
#
# This is a COPY of infra/gcp/client-repo-template/ from leansec-nuclei,
# pushed to your own private repo. `source` below is a version-pinned git
# reference, not a relative path — this repo has no local checkout of the
# leansec-nuclei Terraform module to point a relative path at.
#
# terraform.tfvars in this repo MUST match the values used in the
# architect's original local bootstrap apply: client_name, project_id,
# region, enable_scheduler, enable_ar_mirror, schedule_cron,
# schedule_timezone, and backend state (see backend.tf). This is not
# advisory — the bootstrap module and this template are two separate
# Terraform root modules writing the same state, and any value set here
# overrides whatever the bootstrap apply set on the next CI apply.
# enable_ar_mirror in particular: if the architect enabled an Artifact
# Registry mirror and this repo doesn't also set enable_ar_mirror = true,
# the client's next CI apply DESTROYS that mirror and every image in it.
#
# Changing client_name or project_id here does not migrate existing
# resources; it orphans them and creates new ones under different names.
# If any of these values need to change, contact the architect first.

module "leansec_nuclei" {
  source = "github.com/eriklacson/leansec-nuclei//infra/gcp?ref=v1.2.3"

  project_id    = var.project_id
  client_name   = var.client_name
  region        = var.region
  scanner_image = var.scanner_image
  targets_file  = "${path.module}/targets.txt"
  profiles_file = "${path.module}/profiles.yaml"

  # Derived the same way backend.tf's bucket name is — the state bucket
  # naming convention (scripts/bootstrap-gcp-client.sh's default) is fixed,
  # so there's nothing here for a client to get wrong or leave out of sync
  # with terraform.tfvars. The module grants the deployer SA objectAdmin on
  # this bucket; roles/storage.admin (project-scoped, also granted to the
  # deployer) already covers it too, so this grant is defense-in-depth —
  # it stays load-bearing if storage.admin is ever narrowed to something
  # less than project-wide, which is a tracked follow-up.
  state_bucket_name = "${var.project_id}-tfstate-leansecurity-nuclei"

  # WIF is what lets this repo's GitHub Actions authenticate to GCP without
  # a long-lived service account key. It must already be provisioned by the
  # architect's local bootstrap apply, scoped to THIS repo's owner/repo —
  # do not flip enable_wif here; it only reflects what's already applied.
  enable_wif            = var.enable_wif
  wif_github_repository = var.wif_github_repository

  # These four must match the architect's bootstrap apply exactly — see the
  # warning in the header comment. They are required, not optional
  # overrides: the bootstrap module (.claude/skills/gcp-deploy/templates/)
  # passes all four explicitly, so any value this repo doesn't also state
  # gets silently reverted to the module default on the next CI apply.
  enable_scheduler = var.enable_scheduler
  enable_ar_mirror = var.enable_ar_mirror

  schedule_cron     = var.schedule_cron
  schedule_timezone = var.schedule_timezone
}

# Module passthrough vars. Real values live in terraform.tfvars; these
# declarations exist so `terraform plan` can resolve them.
variable "project_id" {
  description = "Client GCP project ID"
  type        = string
}

variable "client_name" {
  description = "Short client identifier"
  type        = string
}

# No default. The module's own default is a :latest tag, and inheriting it
# silently would put a floating image in a production deployment — against
# the pinning rule in docs/setup-guide.md and infra/gcp/README.md. Required
# here so an unset value fails at plan time instead.
variable "scanner_image" {
  description = "Scanner image URI, pinned to a semver tag. Never :latest."
  type        = string
}

# No default either, and deliberately so. The module default is
# asia-southeast1; a client in another region who never sets this gets a
# plan that relocates every regional resource, surfacing as a destructive
# diff in a PR comment rather than being prevented.
variable "region" {
  description = "GCP region for all regional resources. Must match the value the architect used in the bootstrap apply."
  type        = string
}

# No defaults on these four. A default here would silently mask a bootstrap
# apply that set a non-default value — exactly the drift this template
# exists to prevent. Get the actual values from the architect (they are the
# same tfvars/deployment.yaml the architect used for the bootstrap apply),
# not from this module's own defaults.
variable "enable_scheduler" {
  description = "Must match the architect's bootstrap apply. Provisions Cloud Scheduler + scheduler SA + invoker binding when true."
  type        = bool
}

variable "enable_ar_mirror" {
  description = "Must match the architect's bootstrap apply. Provisions an Artifact Registry mirror repo when true — setting this wrong destroys or fails to create that repo on the next CI apply."
  type        = bool
}

variable "schedule_cron" {
  description = "Must match the architect's bootstrap apply. Cron expression for the scheduled scan."
  type        = string
}

variable "schedule_timezone" {
  description = "Must match the architect's bootstrap apply. Timezone for the scheduler."
  type        = string
}

variable "enable_wif" {
  description = "Must be true — this repo's GitHub Actions workflows authenticate via WIF. Set to false only if you're deliberately disabling CI-driven deploys."
  type        = bool
  default     = true
}

variable "wif_github_repository" {
  description = "This repo's own owner/repo, exactly as provided to the architect before the initial bootstrap apply"
  type        = string
}
