variable "project_id" {
  description = "Client GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region for all resources"
  type        = string
  default     = "asia-southeast1"
}

variable "client_name" {
  description = "Short client identifier (e.g., mdi)"
  type        = string
}

variable "scanner_image" {
  description = "Docker image URI in Artifact Registry"
  type        = string
}

variable "schedule_cron" {
  description = "Cron expression for scan schedule"
  type        = string
  default     = "0 2 1-7 * 0"
}

variable "schedule_timezone" {
  description = "Timezone for scheduler"
  type        = string
  default     = "UTC"
}

variable "targets_file" {
  description = "Path to client target list file in repo"
  type        = string
}

variable "profiles_file" {
  description = "Path to profiles.yaml in repo"
  type        = string
  default     = "scanner/profiles/profiles.yaml"
}

variable "results_retention_days" {
  description = "Days before Nearline transition"
  type        = number
  default     = 365
}

variable "results_delete_days" {
  description = "Days before deletion"
  type        = number
  default     = 730
}

variable "job_memory" {
  description = "Container memory allocation"
  type        = string
  default     = "2Gi"
}

variable "job_cpu" {
  description = "Container CPU allocation"
  type        = string
  default     = "1"
}

variable "job_timeout" {
  description = "Container execution timeout"
  type        = string
  default     = "3600s"
}
