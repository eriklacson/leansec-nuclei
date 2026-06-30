# Example deployment — template only.
# Copy this folder to deployments/<your-client>/ inside the repo checkout.
# Do NOT run terraform apply from this path. See docs/setup-guide.md.

# Module call. `source` is a relative path that resolves correctly when this
# folder is copied to deployments/<client>/ inside the repo checkout.
module "nuclei" {
  source = "../../infra/gcp"

  project_id    = var.project_id
  client_name   = var.client_name
  scanner_image = var.scanner_image
  targets_file  = "${path.module}/targets.txt"
  profiles_file = "${path.module}/profiles.yaml"

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
  default     = "ghcr.io/eriklacson/leansec-nuclei:latest"
}
