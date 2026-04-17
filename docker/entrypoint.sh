#!/bin/bash
set -euo pipefail

# ─── Environment ───
CLOUD_PROVIDER="${CLOUD_PROVIDER:-local}"
CONFIG_BUCKET="${CONFIG_BUCKET:-}"
RESULTS_BUCKET="${RESULTS_BUCKET:-}"
TARGETS_PATH="${TARGETS_PATH:-targets/targets.txt}"
PROFILES_PATH="${PROFILES_PATH:-profiles/profiles.yaml}"
SCAN_DATE=$(date +%Y-%m)
WORK_DIR="/tmp/nuclei-scan"

mkdir -p ${WORK_DIR}/{config,results}

# ─── Cloud storage dispatch ───
download_config() {
  case ${CLOUD_PROVIDER} in
    local)
      cp /opt/nuclei/config/targets.txt ${WORK_DIR}/config/targets.txt
      cp /opt/nuclei/config/profiles.yaml ${WORK_DIR}/config/profiles.yaml 2>/dev/null || true
      ;;
    gcp)
      gcloud storage cp ${CONFIG_BUCKET}/${TARGETS_PATH} ${WORK_DIR}/config/targets.txt
      gcloud storage cp ${CONFIG_BUCKET}/${PROFILES_PATH} ${WORK_DIR}/config/profiles.yaml
      ;;
    aws)
      aws s3 cp s3://${CONFIG_BUCKET}/${TARGETS_PATH} ${WORK_DIR}/config/targets.txt
      aws s3 cp s3://${CONFIG_BUCKET}/${PROFILES_PATH} ${WORK_DIR}/config/profiles.yaml
      ;;
    azure)
      az storage blob download --container ${CONFIG_BUCKET} \
        --name ${TARGETS_PATH} --file ${WORK_DIR}/config/targets.txt
      az storage blob download --container ${CONFIG_BUCKET} \
        --name ${PROFILES_PATH} --file ${WORK_DIR}/config/profiles.yaml
      ;;
    *) echo "Unsupported provider: ${CLOUD_PROVIDER}"; exit 1 ;;
  esac
}

upload_results() {
  case ${CLOUD_PROVIDER} in
    local)
      cp ${WORK_DIR}/results/*.jsonl /opt/nuclei/output/ 2>/dev/null || true
      echo "Results available in mounted output directory."
      ;;
    gcp)
      gcloud storage cp ${WORK_DIR}/results/*.jsonl \
        ${RESULTS_BUCKET}/${SCAN_DATE}/
      ;;
    aws)
      aws s3 cp ${WORK_DIR}/results/ \
        s3://${RESULTS_BUCKET}/${SCAN_DATE}/ --recursive --exclude "*" --include "*.jsonl"
      ;;
    azure)
      for f in ${WORK_DIR}/results/*.jsonl; do
        az storage blob upload --container ${RESULTS_BUCKET} \
          --name ${SCAN_DATE}/$(basename $f) --file $f
      done
      ;;
  esac
}

# ─── Setup ───
download_config
nuclei -update-templates -silent

TARGETS="${WORK_DIR}/config/targets.txt"
OUT="${WORK_DIR}/results"

# ─── Scan Profiles ───

nuclei -l ${TARGETS} \
  -tags misconfig,headers,cors,ssl,tls,exposure,backup,secret,default-login \
  -s medium,high,critical \
  -rl 3 -c 2 -retries 2 -timeout 5 \
  -je ${OUT}/baseline_web_${SCAN_DATE}.jsonl -silent || true

nuclei -l ${TARGETS} \
  -tags cve,wordpress,confluence,jira,gitlab,jenkins,grafana \
  -s high,critical \
  -rl 3 -c 2 -retries 2 -timeout 5 \
  -je ${OUT}/patch_cve_${SCAN_DATE}.jsonl -silent || true

nuclei -l ${TARGETS} \
  -tags default-login,auth,admin-panel,exposure \
  -s high,critical \
  -rl 3 -c 2 -retries 2 -timeout 5 \
  -je ${OUT}/identity_${SCAN_DATE}.jsonl -silent || true

nuclei -l ${TARGETS} \
  -tags secret,exposure,backup,s3,cloud,git,env,token \
  -s medium,high,critical \
  -rl 3 -c 2 -retries 2 -timeout 5 \
  -je ${OUT}/data_protection_${SCAN_DATE}.jsonl -silent || true

nuclei -l ${TARGETS} \
  -tags ssl,tls,headers,hsts \
  -s medium,high \
  -rl 3 -c 2 -retries 2 -timeout 5 \
  -je ${OUT}/transport_${SCAN_DATE}.jsonl -silent || true

nuclei -l ${TARGETS} -im single \
  -tags xss,sqli,ssrf,lfi,rfi,xxe,csrf,open-redirect,cmdi,ssti \
  -s info,low,medium,high,critical \
  -rl 10 -c 50 -retries 2 -timeout 10 \
  -je ${OUT}/owasp_top10_${SCAN_DATE}.jsonl -silent || true

nuclei -l ${TARGETS} \
  -tags cve \
  -s high,critical \
  -rl 3 -c 2 -retries 2 -timeout 5 \
  -je ${OUT}/vuln_monitoring_${SCAN_DATE}.jsonl -silent || true

# ─── Upload ───
upload_results

if [ "${CLOUD_PROVIDER}" = "local" ]; then
  echo "Scan complete. Results in /opt/nuclei/output/"
else
  echo "Scan complete. Results uploaded to ${RESULTS_BUCKET}/${SCAN_DATE}/"
fi
