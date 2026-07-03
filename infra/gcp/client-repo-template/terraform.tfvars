# Populated from the deployment.yaml the architect used for the initial
# local bootstrap apply (see ../deployment.yaml in this repo for the
# human-readable record). These values MUST match that apply exactly —
# see the warning in main.tf.

project_id  = "<your-gcp-project>"
client_name = "<your-client>"

scanner_image = "ghcr.io/eriklacson/leansec-nuclei:latest"

enable_wif            = true
wif_github_repository = "<your-github-owner>/<this-repo-name>"
