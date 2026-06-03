#!/usr/bin/env bash
# bootstrap-gcp-client.sh — one-shot, idempotent GCP project bootstrap for
# the leansecurity-nuclei pipeline.
#
# Steps:
#   1. Set the active gcloud project.
#   2. Enable the required GCP APIs.
#   3. Create the Terraform state bucket (with versioning), if absent.
#   4. Print the IAM roles the client admin must grant.
#   5. Print next steps.
#
# Inputs:
#   $1  GCP project ID (required)
#   $2  Region for the state bucket (optional; default asia-southeast1)
#   $3  State bucket name (optional; default <project_id>-tfstate-leansecurity-nuclei)
#
# Prerequisites:
#   - gcloud CLI installed and authenticated (`gcloud auth login`)
#   - The executing principal has, at minimum, Project Viewer + Service
#     Usage Admin + Storage Admin on the target project, or is a Project
#     Editor/Owner. See the IAM-grant message this script prints.
#
# Exit codes:
#   0   on success or no-op (all resources already present)
#   1   on usage error
#   >1  on gcloud failure (the underlying gcloud exit code propagates)

set -euo pipefail

# ─── usage ──────────────────────────────────────────────────────────────
usage() {
  cat <<'EOF'
Usage: bootstrap-gcp-client.sh <project-id> [region] [state-bucket-name]

Bootstraps a GCP project for the leansecurity-nuclei pipeline:
  - sets the active gcloud project
  - enables required APIs
  - creates a Terraform state bucket with versioning enabled
  - prints the IAM grants required from the client admin
  - prints next steps

Defaults:
  region              asia-southeast1
  state-bucket-name   <project-id>-tfstate-leansecurity-nuclei
EOF
}

# Handle --help before the positional check so `--help` always exits 0.
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

# Required positional arg: project id.
if [[ $# -lt 1 ]]; then
  usage >&2
  exit 1
fi

PROJECT_ID="$1"
REGION="${2:-asia-southeast1}"
STATE_BUCKET="${3:-${PROJECT_ID}-tfstate-leansecurity-nuclei}"

# ─── 1. set active project ──────────────────────────────────────────────
# gcloud config set is local to the workstation; no API call.
echo ">> Setting active gcloud project to ${PROJECT_ID}"
gcloud config set project "${PROJECT_ID}"

# ─── 2. enable APIs ─────────────────────────────────────────────────────
# Enable all APIs the module may touch under any combination of flags.
# `services enable` is idempotent and accepts the full set in one call,
# so re-runs are cheap.
echo ">> Enabling required APIs"
gcloud services enable \
  run.googleapis.com \
  storage.googleapis.com \
  iam.googleapis.com \
  cloudscheduler.googleapis.com \
  iamcredentials.googleapis.com \
  sts.googleapis.com \
  artifactregistry.googleapis.com \
  --project="${PROJECT_ID}"

# ─── 3. state bucket ────────────────────────────────────────────────────
# Probe first; only create on not-found. Versioning is enabled separately
# so re-running against an existing bucket doesn't error out.
echo ">> Ensuring Terraform state bucket gs://${STATE_BUCKET} exists"
if gcloud storage buckets describe "gs://${STATE_BUCKET}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  echo "   bucket already exists, skipping create"
else
  gcloud storage buckets create "gs://${STATE_BUCKET}" \
    --project="${PROJECT_ID}" \
    --location="${REGION}" \
    --uniform-bucket-level-access
fi

# Versioning is required so a corrupted apply can be rolled back without
# state-file forensics. Idempotent — safe to call repeatedly.
gcloud storage buckets update "gs://${STATE_BUCKET}" \
  --project="${PROJECT_ID}" \
  --versioning

# ─── 4. IAM grants ──────────────────────────────────────────────────────
# Print, do not apply. The architect typically can't grant their own
# roles; the client admin does this out-of-band.
cat <<EOF

────────────────────────────────────────────────────────────────────────
IAM grants required on project ${PROJECT_ID}
────────────────────────────────────────────────────────────────────────
The principal running 'terraform apply' (your gcloud identity) needs the
following roles on this project. Ask the client admin to grant them:

  roles/run.admin                          # Cloud Run jobs
  roles/iam.serviceAccountAdmin            # scanner + scheduler SAs
  roles/iam.serviceAccountUser             # use the scanner SA
  roles/storage.admin                      # config + results buckets
  roles/cloudscheduler.admin               # scheduler job (if enabled)
  roles/iam.workloadIdentityPoolAdmin      # WIF (if enabled)
  roles/artifactregistry.admin             # AR mirror (if enabled)

To check what you currently have:
  gcloud projects get-iam-policy ${PROJECT_ID} \\
    --flatten='bindings[].members' \\
    --filter='bindings.members:\$(gcloud config get-value account)'

EOF

# ─── 5. next steps ──────────────────────────────────────────────────────
cat <<EOF
────────────────────────────────────────────────────────────────────────
Next steps
────────────────────────────────────────────────────────────────────────
1. Copy deployments/_example/ to your private storage:
     cp -r deployments/_example/ /path/to/private/<client>/

2. Edit terraform.tfvars in your copy:
     project_id    = "${PROJECT_ID}"
     client_name   = "<client>"
     scanner_image = "ghcr.io/leansecurity/leansec-nuclei:vX.Y.Z"
     targets_file  = "targets.txt"

3. Edit backend.tf to point at the state bucket:
     bucket = "${STATE_BUCKET}"

4. Populate targets.txt with one URL per line.

5. From the deployment folder:
     terraform init
     terraform plan
     terraform apply

See docs/setup-guide.md for the full walkthrough.

EOF
