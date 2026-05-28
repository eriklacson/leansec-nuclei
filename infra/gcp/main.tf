# ─── Storage Buckets ───
# config: holds targets.txt + profiles.yaml the Cloud Run job reads at start.
# results: holds raw JSONL + the normalized JSON envelope the job writes at end.

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

  # Tier scan output to Nearline after results_retention_days; delete after
  # results_delete_days. The matches_prefix scopes both rules to the
  # nuclei/ subtree so non-scan objects (if ever added) are untouched.
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
# scanner: identity Cloud Run runs as; reads config, writes results.
# scheduler: identity Cloud Scheduler uses to invoke the Cloud Run job.

resource "google_service_account" "scanner" {
  project      = var.project_id
  account_id   = "${var.client_name}-nuclei-scanner"
  display_name = "Nuclei Scanner (${var.client_name})"
}

resource "google_service_account" "scheduler" {
  count        = var.enable_scheduler ? 1 : 0
  project      = var.project_id
  account_id   = "${var.client_name}-nuclei-sched"
  display_name = "Nuclei Scheduler (${var.client_name})"
}

# ─── IAM ───
# Scanner needs read on config, read/write on results.

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
# Single Cloud Run job per client. Scheduler triggers it; an architect can
# also invoke manually via `gcloud run jobs execute`.

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

        # Env vars consumed by docker/entrypoint.sh. CLOUD_PROVIDER selects
        # the cloud-IO dispatch path; the bucket envs tell it where to read
        # config from and write results to.
        env {
          name  = "CLOUD_PROVIDER"
          value = "gcp"
        }
        env {
          name  = "CONFIG_BUCKET"
          value = "gs://${google_storage_bucket.config.name}"
        }
        env {
          name  = "RESULTS_BUCKET"
          value = "gs://${google_storage_bucket.results.name}/nuclei"
        }
        env {
          name  = "TARGETS_PATH"
          value = "targets/targets.txt"
        }
        env {
          name  = "CLIENT"
          value = var.client_name
        }
      }
    }
  }
}

# ─── Cloud Scheduler ───
# Provisioned only when enable_scheduler = true. The scheduler SA needs
# run.invoker on the job so the scheduled HTTP POST is authorized.

resource "google_cloud_run_v2_job_iam_member" "scheduler_invoker" {
  count    = var.enable_scheduler ? 1 : 0
  project  = var.project_id
  name     = google_cloud_run_v2_job.nuclei.name
  location = var.region
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.scheduler[0].email}"
}

resource "google_cloud_scheduler_job" "nuclei" {
  count     = var.enable_scheduler ? 1 : 0
  name      = "${var.client_name}-nuclei-monthly"
  project   = var.project_id
  region    = var.region
  schedule  = var.schedule_cron
  time_zone = var.schedule_timezone

  http_target {
    http_method = "POST"
    uri         = "https://${var.region}-run.googleapis.com/apis/run.googleapis.com/v1/namespaces/${var.project_id}/jobs/${google_cloud_run_v2_job.nuclei.name}:run"

    oauth_token {
      service_account_email = google_service_account.scheduler[0].email
    }
  }
}

# ─── Workload Identity Federation ───
# Provisioned only when enable_wif = true. Binds GitHub Actions OIDC
# tokens from var.wif_github_repository to the scanner SA so external CI
# can trigger jobs without long-lived keys.

resource "google_iam_workload_identity_pool" "ci" {
  count                     = var.enable_wif ? 1 : 0
  project                   = var.project_id
  workload_identity_pool_id = "${var.client_name}-ci-pool"
  display_name              = "Nuclei CI Pool (${var.client_name})"
}

resource "google_iam_workload_identity_pool_provider" "github" {
  count                              = var.enable_wif ? 1 : 0
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.ci[0].workload_identity_pool_id
  workload_identity_pool_provider_id = "github"
  display_name                       = "GitHub OIDC"

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
  }

  # Restrict the provider to a single GitHub repo so any other GitHub
  # token presented to this pool is rejected before SA-binding evaluation.
  attribute_condition = "attribute.repository == \"${var.wif_github_repository}\""

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

resource "google_service_account_iam_member" "wif_scanner_binding" {
  count              = var.enable_wif ? 1 : 0
  service_account_id = google_service_account.scanner.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.ci[0].name}/attribute.repository/${var.wif_github_repository}"
}

# ─── Artifact Registry Mirror ───
# Provisioned only when enable_ar_mirror = true. Creates an empty Docker
# repo; the architect performs the GHCR-to-AR mirror push manually after
# apply, then sets scanner_image to the AR URI in a follow-up plan.

resource "google_artifact_registry_repository" "scanner_mirror" {
  count         = var.enable_ar_mirror ? 1 : 0
  project       = var.project_id
  location      = var.region
  repository_id = "${var.client_name}-nuclei"
  format        = "DOCKER"
  description   = "GHCR mirror for the Nuclei scanner image"
}

# ─── Config File Uploads ───
# Push the client's targets.txt and the canonical profiles.yaml into the
# config bucket so the Cloud Run job reads from a known location.

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
