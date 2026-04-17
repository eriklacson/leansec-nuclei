terraform {
  backend "gcs" {
    bucket = "mdi-terraform-state"
    prefix = "nuclei-scanner"
  }
}
