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
# architect's original local bootstrap apply (same client_name, same
# project_id, same backend state — see backend.tf). Changing client_name
# or project_id here does not migrate existing resources; it orphans them
# and creates new ones under different names. If those values need to
# change, contact the architect first.

module "leansec_nuclei" {
  source = "github.com/eriklacson/leansec-nuclei//infra/gcp?ref=v1.2.3"

  project_id    = var.project_id
  client_name   = var.client_name
  scanner_image = var.scanner_image
  targets_file  = "${path.module}/targets.txt"
  profiles_file = "${path.module}/profiles.yaml"

  # WIF is what lets this repo's GitHub Actions authenticate to GCP without
  # a long-lived service account key. It must already be provisioned by the
  # architect's local bootstrap apply, scoped to THIS repo's owner/repo —
  # do not flip enable_wif here; it only reflects what's already applied.
  enable_wif            = var.enable_wif
  wif_github_repository = var.wif_github_repository

  # Feature flags — uncomment to override defaults.
  # enable_scheduler = true
  # enable_ar_mirror = false

  # Override scheduling defaults if needed.
  # region            = "asia-southeast1"
  # schedule_cron     = "0 2 1-7 * 0"
  # schedule_timezone = "UTC"
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

variable "scanner_image" {
  description = "Scanner image URI, pinned to a semver tag for production"
  type        = string
  default     = "ghcr.io/eriklacson/leansec-nuclei:latest"
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
