terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

# ─── Storage Buckets ───

resource "google_storage_bucket" "config" {
  name                        = "${var.client_name}-nuclei-config"
  project                     = var.project_id
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = false
}

resource "google_storage_bucket" "results" {
  name                        = "${var.client_name}-security-scans"
  project                     = var.project_id
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = false

  lifecycle_rule {
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
    condition {
      age            = var.results_retention_days
      matches_prefix = ["nuclei/"]
    }
  }

  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      age            = var.results_delete_days
      matches_prefix = ["nuclei/"]
    }
  }
}

# ─── Service Accounts ───

resource "google_service_account" "scanner" {
  project      = var.project_id
  account_id   = "${var.client_name}-nuclei-scanner"
  display_name = "Nuclei Scanner (${var.client_name})"
}

resource "google_service_account" "scheduler" {
  project      = var.project_id
  account_id   = "${var.client_name}-nuclei-sched"
  display_name = "Nuclei Scheduler (${var.client_name})"
}

# ─── IAM ───

resource "google_storage_bucket_iam_member" "scanner_config_read" {
  bucket = google_storage_bucket.config.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.scanner.email}"
}

resource "google_storage_bucket_iam_member" "scanner_results_write" {
  bucket = google_storage_bucket.results.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.scanner.email}"
}

# ─── Cloud Run Job ───

resource "google_cloud_run_v2_job" "nuclei" {
  name     = "${var.client_name}-nuclei-scan"
  project  = var.project_id
  location = var.region

  template {
    task_count = 1
    template {
      timeout         = var.job_timeout
      max_retries     = 1
      service_account = google_service_account.scanner.email

      containers {
        image = var.scanner_image

        resources {
          limits = {
            cpu    = var.job_cpu
            memory = var.job_memory
          }
        }

        env { name = "CLOUD_PROVIDER" value = "gcp" }
        env { name = "CONFIG_BUCKET"  value = "gs://${google_storage_bucket.config.name}" }
        env { name = "RESULTS_BUCKET" value = "gs://${google_storage_bucket.results.name}/nuclei" }
        env { name = "TARGETS_PATH"   value = "targets/targets.txt" }
        env { name = "PROFILES_PATH"  value = "profiles/profiles.yaml" }
      }
    }
  }
}

# ─── Cloud Scheduler ───

resource "google_cloud_run_v2_job_iam_member" "scheduler_invoker" {
  project  = var.project_id
  name     = google_cloud_run_v2_job.nuclei.name
  location = var.region
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.scheduler.email}"
}

resource "google_cloud_scheduler_job" "nuclei" {
  name      = "${var.client_name}-nuclei-monthly"
  project   = var.project_id
  region    = var.region
  schedule  = var.schedule_cron
  time_zone = var.schedule_timezone

  http_target {
    http_method = "POST"
    uri         = "https://${var.region}-run.googleapis.com/apis/run.googleapis.com/v1/namespaces/${var.project_id}/jobs/${google_cloud_run_v2_job.nuclei.name}:run"

    oauth_token {
      service_account_email = google_service_account.scheduler.email
    }
  }
}

# ─── Config File Uploads ───

resource "google_storage_bucket_object" "targets" {
  name   = "targets/targets.txt"
  bucket = google_storage_bucket.config.name
  source = var.targets_file
}

resource "google_storage_bucket_object" "profiles" {
  name   = "profiles/profiles.yaml"
  bucket = google_storage_bucket.config.name
  source = var.profiles_file
}
