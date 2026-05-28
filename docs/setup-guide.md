# Setup Guide — Cloud Deployment (GCP)

End-to-end walkthrough for deploying the `leansecurity-nuclei` pipeline to your own GCP project. Each step lists the expected output so you can verify success before moving on.

Architecture context: [`gcp_architecture.md`](gcp_architecture.md). Module reference: [`infra/gcp/README.md`](../infra/gcp/README.md).

---

## Prerequisites

You need:

- **GCP project** you control, with billing enabled.
- **gcloud CLI** installed and authenticated:
  ```bash
  gcloud auth login
  gcloud auth application-default login
  ```
- **Terraform** >= 1.8 installed locally.
- **A private storage location** for this client's deployment folder. It can be a private git repo, an encrypted shared drive, or any storage your team controls. **It must not be a fork of the public `leansecurity-nuclei` repo.**
- **IAM on the target project** — see the IAM section of [`infra/gcp/README.md`](../infra/gcp/README.md#prerequisites). The bootstrap script prints the exact role list.

---

## Step 1 — Bootstrap the GCP project

Run the bootstrap script once per GCP project. It enables required APIs and creates the Terraform state bucket.

```bash
./scripts/bootstrap-gcp-client.sh <your-project-id>
```

Optional arguments:

```bash
./scripts/bootstrap-gcp-client.sh <your-project-id> <region> <state-bucket-name>
```

Defaults: region `asia-southeast1`; state bucket `<your-project-id>-tfstate-leansecurity-nuclei`.

**Expected output (excerpt):**

```
>> Setting active gcloud project to <your-project-id>
>> Enabling required APIs
Operation "operations/acat.p2-..." finished successfully.
>> Ensuring Terraform state bucket gs://<your-project-id>-tfstate-leansecurity-nuclei exists
Creating gs://<your-project-id>-tfstate-leansecurity-nuclei/...
...
IAM grants required on project <your-project-id>
────────────────────────────────────────────────────────────────────────
```

If you re-run the script, the bucket-create step will say `bucket already exists, skipping create`. That is the idempotent path.

---

## Step 2 — Copy the example folder to your private storage

```bash
cp -r deployments/_example/ /path/to/private/<your-client-name>/
cd /path/to/private/<your-client-name>/
```

From this point forward, all commands run from inside the private copy, not from the public repo.

---

## Step 3 — Configure `terraform.tfvars`

Edit `terraform.tfvars` and replace the placeholders:

```hcl
project_id    = "<your-project-id>"
client_name   = "<your-client-name>"
scanner_image = "ghcr.io/leansecurity/nuclei-scanner:v1.0.0"
```

Notes:

- `client_name` must be valid as a GCS bucket name prefix and a service account ID prefix — lowercase letters, digits, hyphens; no underscores.
- Pin `scanner_image` to a semver tag (or `:<short-sha>`). **Do not use `:latest` in production** — it produces non-reproducible deploys.

---

## Step 4 — Configure `backend.tf`

Edit `backend.tf` so the bucket name matches the state bucket created in step 1:

```hcl
terraform {
  backend "gcs" {
    bucket = "<your-project-id>-tfstate-leansecurity-nuclei"
    prefix = "nuclei-scanner"
  }
}
```

---

## Step 5 — Populate `targets.txt`

One URL per line. Lines starting with `#` are comments.

```
https://www.example.com
https://api.example.com
```

The file is uploaded to the config bucket as `targets/targets.txt` on `terraform apply`; the Cloud Run job reads it at scan time.

---

## Step 6 — `terraform init`

```bash
terraform init
```

**Expected output (last lines):**

```
Successfully configured the backend "gcs"! Terraform will automatically
use this backend unless the backend configuration changes.
...
Terraform has been successfully initialized!
```

If init fails with `Failed to get existing workspaces: querying Cloud Storage failed: ... permission denied`, your gcloud identity does not have `roles/storage.admin` on the state bucket. See troubleshooting.

---

## Step 7 — `terraform plan`

```bash
terraform plan
```

**Expected output (summary):**

```
Plan: 12 to add, 0 to change, 0 to destroy.
```

The exact count depends on the flag combination. With defaults (`enable_scheduler = true`, `enable_wif = false`, `enable_ar_mirror = false`) you should see:

- 2 storage buckets (config, results)
- 1 Cloud Run job
- 2 service accounts (scanner, scheduler)
- 2 IAM bindings on buckets
- 1 IAM binding for scheduler invoker
- 1 Cloud Scheduler job
- 2 storage bucket objects (targets, profiles)

Review the plan. If a resource shows an unexpected name or a missing field, stop and check `terraform.tfvars`.

---

## Step 8 — `terraform apply`

```bash
terraform apply
```

Type `yes` when prompted.

**Expected output (last lines):**

```
Apply complete! Resources: 12 added, 0 changed, 0 destroyed.

Outputs:

cloud_run_job_name = "<client>-nuclei-scan"
config_bucket_name = "<client>-nuclei-config"
results_bucket_name = "<client>-security-scans"
scheduler_job_name = "<client>-nuclei-monthly"
scanner_service_account_email = "<client>-nuclei-scanner@<project>.iam.gserviceaccount.com"
```

---

## Step 9 — Trigger the first scan manually

```bash
gcloud run jobs execute <client>-nuclei-scan \
  --project <your-project-id> \
  --region asia-southeast1 \
  --wait
```

`--wait` blocks until the job exits. A baseline scan takes 5–15 minutes depending on target count.

**Expected output (last line):**

```
Execution [<client>-nuclei-scan-xxxxx] has successfully completed.
```

If the job fails with `Image pull failed`, see troubleshooting.

---

## Step 10 — Verify JSONL output

```bash
gcloud storage ls gs://<client>-security-scans/nuclei/$(date +%Y-%m)/
```

**Expected output:**

```
gs://<client>-security-scans/nuclei/YYYY-MM/baseline_web_YYYY-MM.jsonl
gs://<client>-security-scans/nuclei/YYYY-MM/data_protection_YYYY-MM.jsonl
gs://<client>-security-scans/nuclei/YYYY-MM/identity_remote_access_YYYY-MM.jsonl
gs://<client>-security-scans/nuclei/YYYY-MM/owasp_top10_core_YYYY-MM.jsonl
gs://<client>-security-scans/nuclei/YYYY-MM/patch_cve_YYYY-MM.jsonl
gs://<client>-security-scans/nuclei/YYYY-MM/result-YYYY-MM-DD.json
gs://<client>-security-scans/nuclei/YYYY-MM/transport_security_YYYY-MM.jsonl
gs://<client>-security-scans/nuclei/YYYY-MM/vuln_monitoring_YYYY-MM.jsonl
```

Filename stems match `scanner/profiles/profiles.yaml` profile keys exactly. The `result-YYYY-MM-DD.json` is the normalized v1 envelope; the per-profile `.jsonl` files are raw Nuclei output.

---

## Step 11 — Confirm Cloud Scheduler is armed

```bash
gcloud scheduler jobs describe <client>-nuclei-monthly \
  --project <your-project-id> \
  --location asia-southeast1 \
  --format='value(scheduleTime,schedule,state)'
```

**Expected output:**

```
<next-execution-timestamp>	0 2 1-7 * 0	ENABLED
```

If state is `PAUSED`, re-enable with `gcloud scheduler jobs resume`.

---

## Ongoing operations

### Change targets

Edit `targets.txt` in your private folder. From inside that folder:

```bash
terraform apply
```

The apply uploads the new file to the config bucket; the next scheduled scan picks it up. No code or image change.

### Bump the scanner image version

When a new `vX.Y.Z` tag is published to GHCR:

```bash
# In terraform.tfvars
scanner_image = "ghcr.io/leansecurity/nuclei-scanner:vX.Y.Z"
```

```bash
terraform apply
```

The Cloud Run job's image reference updates; the next execution pulls the new tag.

### Disable the scheduler

To stop the autonomous monthly scan (e.g. during an engagement pause):

```hcl
# In terraform.tfvars or as a flag override
enable_scheduler = false
```

```bash
terraform apply
```

The scheduler resources are destroyed; the Cloud Run job is preserved and can still be invoked manually with `gcloud run jobs execute`. Re-enable by removing the flag override and re-applying.

---

## Troubleshooting

### API not enabled

```
Error: googleapi: Error 403: Cloud Run Admin API has not been used in project ...
```

The bootstrap script enables all APIs the module needs. If you skipped it, run it now:

```bash
./scripts/bootstrap-gcp-client.sh <your-project-id>
```

You can also enable a specific API by hand:

```bash
gcloud services enable run.googleapis.com --project <your-project-id>
```

### IAM permission denied

```
Error: googleapi: Error 403: ... does not have permission ...
```

Your gcloud identity is missing one or more roles on the target project. Check what you have:

```bash
gcloud projects get-iam-policy <your-project-id> \
  --flatten='bindings[].members' \
  --filter='bindings.members:'$(gcloud config get-value account)
```

Ask the client admin to grant the roles printed by the bootstrap script.

### Terraform state bucket access denied

```
Error: Failed to get existing workspaces: querying Cloud Storage failed: ... permission denied
```

You can't read the state bucket your `backend.tf` points at. Two common causes:

1. The bucket name in `backend.tf` doesn't match the bucket the bootstrap script created. Compare carefully.
2. Your identity has no `roles/storage.admin` (or at least `roles/storage.objectUser`) on the state bucket.

```bash
gcloud storage buckets describe gs://<state-bucket-name> --project <your-project-id>
```

### Scanner image pull failure

In the Cloud Run job logs:

```
Error: Image '<...>:<...>' is not accessible from your project ...
```

Possible causes:

1. **GHCR rate limit / anonymous pull blocked.** GHCR allows anonymous pulls for public images, but some networks block egress. If this is the issue, enable `enable_ar_mirror = true`, mirror the GHCR image into the client's AR, and re-apply with `scanner_image` pointed at the AR URI. See the [module reference](../infra/gcp/README.md#enable_ar_mirror-default-false).
2. **Typo in the image tag.** Verify the tag exists at [ghcr.io/leansecurity/nuclei-scanner](https://ghcr.io/leansecurity/nuclei-scanner).
3. **Scanner SA lacks AR read** (only when mirroring). Grant `roles/artifactregistry.reader` to the scanner SA on the AR repo.

### Cloud Run job timeout

```
Execution [<job>-xxxxx] failed: container exited with code 124 (timeout)
```

The job exceeded `job_timeout` (default 1 hour). Two paths:

1. **Reduce target count.** Large `targets.txt` lists with many active profiles can run long. Split into multiple deployments if needed.
2. **Increase the timeout.** In `terraform.tfvars`:
   ```hcl
   # not a defined variable in _example/ by default; pass to the module if needed
   job_timeout = "7200s"
   ```
   Then re-apply. Maximum Cloud Run job timeout is 24 hours.

If the job hangs without finishing a profile, check Cloud Run logs for the offending profile — it may indicate a target that consistently times out the Nuclei runner.

---

## See also

- [Architecture](gcp_architecture.md)
- [Module reference](../infra/gcp/README.md)
- [Root README](../README.md)
