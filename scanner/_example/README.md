# Local CLI Deployment — Template

This folder is a **template**. Copy it to `deployments/<your-client>/` inside
the repo checkout to set up a local CLI scan.

## What you need

- Nuclei installed (`brew install nuclei` or `go install github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest`)
- This repo cloned locally

## Setup

1. **Copy this folder** to your deployment folder:
   ```bash
   cp -r scanner/_example/ deployments/<your-client>/
   cd deployments/<your-client>/
   ```
   The `deployments/<client>/` folder is gitignored.

2. **Populate `targets.txt`** with real external URLs (one per line).

3. **Run the scan** from the repo root:
   ```bash
   ./scanner/scan.py <your-client>
   ```

Results land in `results/<your-client>/YYYY-MM/` mirroring the cloud layout.

## Pushing results to GCS (optional)

If you want to upload local results to a GCS bucket:

1. Copy `.env.example` to `deployments/<your-client>/.env` and fill in your
   GCP project and bucket.
2. Use `gcloud storage cp` as shown in the root README.

## See also

- [`docs/setup-guide.md`](../../docs/setup-guide.md)
- [`scanner/scan.py`](../scan.py) — scanner entry point
- [`scanner/profiles/profiles.yaml`](../profiles/profiles.yaml) — scan profiles
