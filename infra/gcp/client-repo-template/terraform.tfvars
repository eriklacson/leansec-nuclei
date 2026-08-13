# Populated from the deployment.yaml the architect used for the initial
# local bootstrap apply (see ../deployment.yaml in this repo for the
# human-readable record). These values MUST match that apply exactly —
# see the warning in main.tf.

project_id  = "<your-gcp-project>"
client_name = "<your-client>"
region      = "<your-region>"

# Pin to the semver tag the architect specified. Never :latest — a floating
# tag means the scanned image can change under you between scheduled runs.
scanner_image = "ghcr.io/eriklacson/leansec-nuclei:<pinned-version>"

# These four must match the architect's bootstrap apply exactly, or the
# next CI apply reverts them to the module default — see the warning in
# main.tf. enable_ar_mirror is the destructive one: get these values from
# the architect, don't guess — the false/defaults below are placeholders,
# not safe fallbacks.
enable_scheduler = false # REPLACE with the architect's actual value
enable_ar_mirror = false # REPLACE with the architect's actual value
schedule_cron     = "<cron-expression>"
schedule_timezone = "<timezone>"

enable_wif            = true
wif_github_repository = "<your-github-owner>/<this-repo-name>"
