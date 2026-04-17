output "config_bucket_name" {
  description = "Name of the config storage bucket"
  value       = google_storage_bucket.config.name
}

output "results_bucket_name" {
  description = "Name of the results storage bucket"
  value       = google_storage_bucket.results.name
}

output "cloud_run_job_name" {
  description = "Name of the Cloud Run job"
  value       = google_cloud_run_v2_job.nuclei.name
}

output "scheduler_job_name" {
  description = "Name of the scheduler job"
  value       = google_cloud_scheduler_job.nuclei.name
}

output "scanner_service_account_email" {
  description = "Email of the scanner service account"
  value       = google_service_account.scanner.email
}
