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

# scheduler_job_name resolves to null when enable_scheduler = false. The
# null literal preserves the output contract so consumers can rely on the
# key always being present.
output "scheduler_job_name" {
  description = "Name of the Cloud Scheduler job; null when enable_scheduler = false"
  value       = var.enable_scheduler ? google_cloud_scheduler_job.nuclei[0].name : null
}

output "scanner_service_account_email" {
  description = "Email of the scanner service account"
  value       = google_service_account.scanner.email
}

# WIF + AR outputs are conditionally populated so private deployments can
# wire downstream tooling (CI workflows, image mirrors) to these values
# without conditional null-checks in calling code beyond the flag itself.
output "wif_pool_name" {
  description = "Full resource name of the WIF pool; null when enable_wif = false"
  value       = var.enable_wif ? google_iam_workload_identity_pool.ci[0].name : null
}

output "wif_provider_name" {
  description = "Full resource name of the WIF GitHub provider; null when enable_wif = false"
  value       = var.enable_wif ? google_iam_workload_identity_pool_provider.github[0].name : null
}

output "artifact_registry_repository" {
  description = "Artifact Registry repository ID for the AR mirror; null when enable_ar_mirror = false"
  value       = var.enable_ar_mirror ? google_artifact_registry_repository.scanner_mirror[0].repository_id : null
}
