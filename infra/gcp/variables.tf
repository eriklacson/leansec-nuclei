# ─── Required ───

variable "project_id" {
  description = "Client GCP project ID"
  type        = string
}

variable "client_name" {
  description = "Short client identifier; used as a prefix for resource names"
  type        = string
}

variable "scanner_image" {
  description = "Scanner image URI. GHCR is the canonical distribution channel; any OCI registry the Cloud Run service account can read is accepted."
  type        = string
  default     = "ghcr.io/eriklacson/leansec-nuclei:latest"
}

variable "targets_file" {
  description = "Local path to the client target list; uploaded to the config bucket on apply"
  type        = string
}

# ─── Optional ───

variable "region" {
  description = "GCP region for all regional resources"
  type        = string
  default     = "asia-southeast1"
}

variable "profiles_file" {
  description = "Local path to profiles.yaml; uploaded to the config bucket on apply"
  type        = string
  default     = "scanner/profiles/profiles.yaml"
}

variable "schedule_cron" {
  description = "Cron expression for the scheduled scan; ignored when enable_scheduler = false"
  type        = string
  default     = "0 2 1-7 * 0"
}

variable "schedule_timezone" {
  description = "Timezone for the scheduler; ignored when enable_scheduler = false"
  type        = string
  default     = "UTC"
}

variable "results_retention_days" {
  description = "Age in days before results bucket objects transition to Nearline"
  type        = number
  default     = 365
}

variable "results_delete_days" {
  description = "Age in days before results bucket objects are deleted"
  type        = number
  default     = 730
}

variable "job_memory" {
  description = "Cloud Run container memory allocation"
  type        = string
  default     = "2Gi"
}

variable "job_cpu" {
  description = "Cloud Run container CPU allocation"
  type        = string
  default     = "1"
}

variable "job_timeout" {
  description = "Cloud Run task timeout"
  type        = string
  default     = "3600s"
}

# ─── Feature flags ───

variable "enable_scheduler" {
  description = "Provision Cloud Scheduler job + scheduler SA + invoker IAM binding"
  type        = bool
  default     = true
}

variable "enable_wif" {
  description = "Provision Workload Identity Federation pool, provider, and SA binding for external CI access. Requires wif_github_repository when true."
  type        = bool
  default     = false
}

variable "enable_ar_mirror" {
  description = "Provision an Artifact Registry repository in this project for mirroring the GHCR scanner image. The mirror push step is performed manually by the architect after apply."
  type        = bool
  default     = false
}

# ─── WIF supporting inputs ───
# Only consumed when enable_wif = true. The current shape supports GitHub
# Actions OIDC; other issuers are out of scope for this revision.

variable "wif_github_repository" {
  description = "GitHub repository (owner/repo) authorized to assume the scanner SA via WIF. Required when enable_wif = true."
  type        = string
  default     = ""
}
