#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────
# GCP Full Alert Setup — metric + policies (paste into Cloud Shell)
# Project: project-5715f613-4d3e-4df5-951
# Service: cloud-incident-tester
# ──────────────────────────────────────────────────────────────────
set -euo pipefail

PROJECT="project-5715f613-4d3e-4df5-951"
SERVICE="cloud-incident-tester"
NOTIF_CHANNEL="projects/$PROJECT/notificationChannels/4314518755853863600"

echo "═══════════════════════════════════════════════════════════"
echo " Setting up metrics + alerting for $SERVICE"
echo "═══════════════════════════════════════════════════════════"

# ── 1. Create log-based metric for HTTP 5xx ───────────────────
echo ""
echo "▸ [1/4] Creating log-based metric: http5xx_errors"
gcloud logging metrics create http5xx_errors \
  --description="Counts HTTP 5xx errors from Cloud Run incident-tester" \
  --log-filter='resource.type="cloud_run_revision" AND resource.labels.service_name="'"$SERVICE"'" AND severity>=ERROR' \
  && echo "  ✓ Metric created" \
  || echo "  ⚠ Metric may already exist (continuing)"

# ── 2. Create HTTP 5xx alerting policy ────────────────────────
echo ""
echo "▸ [2/4] Creating alerting policy: HTTP 5xx Errors"
cat > /tmp/alert_5xx.json << ENDJSON
{
  "displayName": "HTTP 5xx Errors - Incident Tester",
  "combiner": "OR",
  "enabled": true,
  "conditions": [
    {
      "displayName": "5xx count > 5 in 2 min window",
      "conditionThreshold": {
        "filter": "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"${SERVICE}\" AND metric.type=\"logging.googleapis.com/user/http5xx_errors\"",
        "aggregations": [
          {
            "alignmentPeriod": "120s",
            "perSeriesAligner": "ALIGN_COUNT",
            "crossSeriesReducer": "REDUCE_SUM",
            "groupByFields": ["resource.labels.service_name"]
          }
        ],
        "comparison": "COMPARISON_GT",
        "thresholdValue": 5,
        "duration": "0s",
        "trigger": {
          "count": 1
        }
      }
    }
  ],
  "alertStrategy": {
    "autoClose": "1800s"
  },
  "notificationChannels": ["${NOTIF_CHANNEL}"]
}
ENDJSON
gcloud monitoring policies create --policy-from-file=/tmp/alert_5xx.json \
  && echo "  ✓ HTTP 5xx policy created" \
  || echo "  ✗ Failed to create HTTP 5xx policy"

# ── 3. Create CPU alerting policy ─────────────────────────────
echo ""
echo "▸ [3/4] Creating alerting policy: High CPU Usage"
cat > /tmp/alert_cpu.json << ENDJSON
{
  "displayName": "High CPU Usage - Incident Tester",
  "combiner": "OR",
  "enabled": true,
  "conditions": [
    {
      "displayName": "CPU utilization > 80%",
      "conditionThreshold": {
        "filter": "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"${SERVICE}\" AND metric.type=\"run.googleapis.com/container/cpu/utilization\"",
        "aggregations": [
          {
            "alignmentPeriod": "120s",
            "perSeriesAligner": "ALIGN_MEAN",
            "crossSeriesReducer": "REDUCE_MEAN",
            "groupByFields": ["resource.labels.service_name"]
          }
        ],
        "comparison": "COMPARISON_GT",
        "thresholdValue": 0.8,
        "duration": "0s",
        "trigger": {
          "count": 1
        }
      }
    }
  ],
  "alertStrategy": {
    "autoClose": "1800s"
  },
  "notificationChannels": ["${NOTIF_CHANNEL}"]
}
ENDJSON
gcloud monitoring policies create --policy-from-file=/tmp/alert_cpu.json \
  && echo "  ✓ CPU policy created" \
  || echo "  ✗ Failed to create CPU policy"

# ── 4. Verify everything ─────────────────────────────────────
echo ""
echo "▸ [4/4] Verification"
echo ""
echo "Log-based metrics:"
gcloud logging metrics list --format="table(name,metricDescriptor.type)" 2>/dev/null
echo ""
echo "Alerting policies:"
gcloud monitoring policies list --format="table(name,displayName,enabled)" 2>/dev/null
echo ""
echo "═══════════════════════════════════════════════════════════"
echo " Done. Now run fault injection to test if alerts fire:"
echo "   python3 gcp_fire.py https://cloud-incident-tester-132317288178.us-central1.run.app"
echo "═══════════════════════════════════════════════════════════"
