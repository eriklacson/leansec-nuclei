#!/bin/bash
set -euo pipefail

# ─── LeanSecurity Nuclei Local Scanner ───
# Usage: ./scan.sh <client-name>
# Example: ./scan.sh mdi
#
# Prerequisites: nuclei installed (brew install nuclei / go install)
# Reads targets from: deployments/<client>/targets.txt
# Writes results to:  results/<client>/YYYY-MM/

CLIENT="${1:?Usage: ./scan.sh <client-name>}"
SCAN_DATE=$(date +%Y-%m)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGETS="${SCRIPT_DIR}/deployments/${CLIENT}/targets.txt"
OUT="${SCRIPT_DIR}/results/${CLIENT}/${SCAN_DATE}"

# ─── Validate ───
if ! command -v nuclei &> /dev/null; then
  echo "Error: nuclei is not installed."
  echo "Install: brew install nuclei (macOS) or go install -v github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest"
  exit 1
fi

if [ ! -f "${TARGETS}" ]; then
  echo "Error: deployments/${CLIENT}/targets.txt not found"
  exit 1
fi

mkdir -p "${OUT}"

# ─── Update templates ───
echo "Updating Nuclei templates..."
nuclei -update-templates -silent

# ─── Scan Profiles ───
echo "Starting scan for ${CLIENT}..."
echo ""

echo "[1/7] baseline_web"
nuclei -l ${TARGETS} \
  -tags misconfig,headers,cors,ssl,tls,exposure,backup,secret,default-login \
  -s medium,high,critical \
  -rl 3 -c 2 -retries 2 -timeout 5 \
  -je ${OUT}/baseline_web_${SCAN_DATE}.jsonl -silent || true

echo "[2/7] patch_cve"
nuclei -l ${TARGETS} \
  -tags cve,wordpress,confluence,jira,gitlab,jenkins,grafana \
  -s high,critical \
  -rl 3 -c 2 -retries 2 -timeout 5 \
  -je ${OUT}/patch_cve_${SCAN_DATE}.jsonl -silent || true

echo "[3/7] identity_remote_access"
nuclei -l ${TARGETS} \
  -tags default-login,auth,admin-panel,exposure \
  -s high,critical \
  -rl 3 -c 2 -retries 2 -timeout 5 \
  -je ${OUT}/identity_${SCAN_DATE}.jsonl -silent || true

echo "[4/7] data_protection"
nuclei -l ${TARGETS} \
  -tags secret,exposure,backup,s3,cloud,git,env,token \
  -s medium,high,critical \
  -rl 3 -c 2 -retries 2 -timeout 5 \
  -je ${OUT}/data_protection_${SCAN_DATE}.jsonl -silent || true

echo "[5/7] transport_security"
nuclei -l ${TARGETS} \
  -tags ssl,tls,headers,hsts \
  -s medium,high \
  -rl 3 -c 2 -retries 2 -timeout 5 \
  -je ${OUT}/transport_${SCAN_DATE}.jsonl -silent || true

echo "[6/7] owasp_top10_core"
nuclei -l ${TARGETS} -im single \
  -tags xss,sqli,ssrf,lfi,rfi,xxe,csrf,open-redirect,cmdi,ssti \
  -s info,low,medium,high,critical \
  -rl 10 -c 50 -retries 2 -timeout 10 \
  -je ${OUT}/owasp_top10_${SCAN_DATE}.jsonl -silent || true

echo "[7/7] vuln_monitoring"
nuclei -l ${TARGETS} \
  -tags cve \
  -s high,critical \
  -rl 3 -c 2 -retries 2 -timeout 5 \
  -je ${OUT}/vuln_monitoring_${SCAN_DATE}.jsonl -silent || true

# ─── Summary ───
echo ""
echo "─── Scan Complete ───"
echo "Client:  ${CLIENT}"
echo "Results: results/${CLIENT}/${SCAN_DATE}/"
echo ""
FINDINGS=$(cat ${OUT}/*.jsonl 2>/dev/null | wc -l | tr -d ' ')
echo "Total findings: ${FINDINGS}"
echo ""
ls -la "${OUT}/" 2>/dev/null
echo ""
echo "To push results to GCS for Conduit:"
echo "  gcloud storage cp ${OUT}/*.jsonl gs://<bucket>/nuclei/${SCAN_DATE}/"
