terraform {
  backend "gcs" {
    bucket = "REPLACE-WITH-CLIENT-terraform-state"
    prefix = "nuclei-scanner"
  }
}
