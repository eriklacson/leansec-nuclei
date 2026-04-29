module "nuclei" {
  source = "../../infra/gcp"

  project_id    = var.project_id
  region        = "asia-southeast1"
  client_name   = "REPLACE"
  scanner_image = var.scanner_image
  targets_file  = "${path.module}/targets.txt"
  profiles_file = "${path.module}/../../scanner/profiles/profiles.yaml"

  schedule_cron     = "0 2 1-7 * 0"
  schedule_timezone = "Asia/Manila"
}

variable "project_id" {
  description = "Client GCP project ID"
  type        = string
}

variable "scanner_image" {
  description = "Docker image URI"
  type        = string
}
