# Pin Terraform core + the google provider. v6+ is required for the
# google_cloud_run_v2_job env-block schema used in main.tf; the v5 schema
# rejects the multi-line `env { name; value }` form we rely on.
terraform {
  required_version = ">= 1.8"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}
