#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────
# GCP Evidence Collection — run in Cloud Shell after fault injection
# Mirrors Azure evidence structure: research/evidence/gcp/session-YYYY-MM-DD/
# ──────────────────────────────────────────────────────────────────
set -euo pipefail

PROJECT=$(gcloud config get-value project)
SERVICE="cloud-incident-tester"
DATE=$(date -u +%Y-%m-%d)
SESSION_DIR="research/evidence/gcp/session-$DATE"

echo "═══════════════════════════════════════════════════════════"
echo " Collecting GCP experiment evidence — $DATE"
echo "═══════════════════════════════════════════════════════════"

mkdir -p "$SESSION_DIR"/{raw,analysis}

# ── 1. Cloud Run logs ─────────────────────────────────────────
echo ""
echo "▸ [1/5] Cloud Run logs..."
gcloud logging read \
  "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"$SERVICE\"" \
  --format=json --limit=5000 > "$SESSION_DIR/raw/cloud_run_logs.json" 2>/dev/null
echo "  ✓ $(python3 -c "import json; print(len(json.load(open('$SESSION_DIR/raw/cloud_run_logs.json'))))" 2>/dev/null || echo '?') entries"

# ── 2. Error-only logs ────────────────────────────────────────
echo "▸ [2/5] Error-level logs..."
gcloud logging read \
  "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"$SERVICE\" AND severity>=ERROR" \
  --format=json --limit=1000 > "$SESSION_DIR/raw/error_logs.json" 2>/dev/null
echo "  ✓ $(python3 -c "import json; print(len(json.load(open('$SESSION_DIR/raw/error_logs.json'))))" 2>/dev/null || echo '?') error entries"

# ── 3. Security Command Center findings ────────────────────────
echo "▸ [3/5] Security Command Center findings..."
ORG_ID=$(gcloud organizations list --format="value(name)" 2>/dev/null | head -1 | sed 's|organizations/||')
if [ -n "$ORG_ID" ]; then
  gcloud scc findings list "organizations/$ORG_ID" \
    --filter="state=ACTIVE" --format=json > "$SESSION_DIR/raw/scc_findings.json" 2>/dev/null
  echo "  ✓ $(python3 -c "import json; print(len(json.load(open('$SESSION_DIR/raw/scc_findings.json'))))" 2>/dev/null || echo '?') findings"
else
  echo "  ⚠  No organization found — SCC findings skipped"
  echo "[]" > "$SESSION_DIR/raw/scc_findings.json"
fi

# ── 4. Alerting policy status / incidents ─────────────────────
echo "▸ [4/5] Alerting incidents..."
gcloud monitoring incidents list \
  --format=json > "$SESSION_DIR/raw/monitoring_incidents.json" 2>/dev/null || echo "[]" > "$SESSION_DIR/raw/monitoring_incidents.json"
echo "  ✓ $(python3 -c "import json; print(len(json.load(open('$SESSION_DIR/raw/monitoring_incidents.json'))))" 2>/dev/null || echo '?') incidents"

# ── 5. Alerting policies snapshot ─────────────────────────────
echo "▸ [5/5] Alerting policies..."
gcloud monitoring policies list --format=json > "$SESSION_DIR/raw/alerting_policies.json" 2>/dev/null
echo "  ✓ $(python3 -c "import json; print(len(json.load(open('$SESSION_DIR/raw/alerting_policies.json'))))" 2>/dev/null || echo '?') policies"

# ── Copy fault injection records ──────────────────────────────
if [ -f incident_responses.jsonl ]; then
  cp incident_responses.jsonl "$SESSION_DIR/raw/"
  echo ""
  echo "  ✓ Copied incident_responses.jsonl"
fi

# ── Log-based metrics snapshot ────────────────────────────────
echo ""
echo "▸ Bonus: Log-based metrics..."
gcloud logging metrics list --format=json > "$SESSION_DIR/raw/log_based_metrics.json" 2>/dev/null

# ── Summary ────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════"
echo " Evidence saved to: $SESSION_DIR/"
echo "═══════════════════════════════════════════════════════════"
ls -la "$SESSION_DIR/raw/"
echo ""
echo "Next: analyze with gcp_analyze.py or manually review the JSON files."
echo "═══════════════════════════════════════════════════════════"
