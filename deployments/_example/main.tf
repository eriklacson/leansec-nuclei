# Example deployment — template only.
# Copy this folder to client-controlled private storage; do NOT deploy
# from this path. See docs/setup-guide.md for the full walkthrough.

# Module call. `source` pulls infra/gcp/ from the public repo at a pinned
# semver tag. Use a tag rather than a branch so the module shape is
# reproducible across applies.
module "nuclei" {
  source = "git::https://github.com/leansecurity/leansecurity-nuclei.git//infra/gcp?ref=v1.0.0"

  project_id    = var.project_id
  client_name   = var.client_name
  scanner_image = var.scanner_image
  targets_file  = "${path.module}/targets.txt"
  profiles_file = "${path.module}/../../scanner/profiles/profiles.yaml"

  # Feature flags — uncomment to override defaults.
  # enable_scheduler      = true
  # enable_wif            = false
  # wif_github_repository = "<owner>/<repo>"
  # enable_ar_mirror      = false

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
  default     = "ghcr.io/leansecurity/nuclei-scanner:v1.0.0"
}
