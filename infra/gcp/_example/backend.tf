# Terraform state lives in a per-client GCS bucket created by
# scripts/bootstrap-gcp-client.sh. Replace <your-project-id> with the
# project ID you passed to the bootstrap script.
terraform {
  backend "gcs" {
    bucket = "<your-project-id>-tfstate-leansecurity-nuclei"
    prefix = "nuclei-scanner"
  }
}
