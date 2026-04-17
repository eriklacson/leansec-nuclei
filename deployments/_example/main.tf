module "nuclei" {
  source = "../../infra/gcp"

  project_id    = var.project_id
  region        = var.region
  client_name   = var.client_name
  scanner_image = var.scanner_image
  targets_file  = "${path.module}/targets.txt"
  profiles_file = "${path.module}/../../scanner/profiles/profiles.yaml"

  # Override defaults if needed
  # schedule_cron     = "0 2 1-7 * 0"
  # schedule_timezone = "UTC"
}

variable "project_id" {
  description = "Client GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "asia-southeast1"
}

variable "client_name" {
  description = "Short client identifier"
  type        = string
}

variable "scanner_image" {
  description = "Docker image URI"
  type        = string
}
