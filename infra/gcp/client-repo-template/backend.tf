# Terraform state lives in a per-client GCS bucket created by
# scripts/bootstrap-gcp-client.sh during the architect's initial local
# bootstrap (see ADR-008). This repo's GitHub Actions continue writing to
# the SAME state — replace <your-project-id> with the project ID the
# architect used, not a new one.
terraform {
  backend "gcs" {
    bucket = "<your-project-id>-tfstate-leansecurity-nuclei"
    prefix = "nuclei-scanner"
  }
}
