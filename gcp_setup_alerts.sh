#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────
# GCP Alert Setup — correct approach for Cloud Run error alerts
# Run in Cloud Shell. Uses built-in Cloud Run metrics (not log-based).
# ──────────────────────────────────────────────────────────────────
set -euo pipefail

PROJECT=$(gcloud config get-value project)
REGION="us-central1"
SERVICE="cloud-incident-tester"

echo "═══════════════════════════════════════════════════════════"
echo " Setting up alerting for $SERVICE in $PROJECT"
echo "═══════════════════════════════════════════════════════════"

# ── Option A: Log-based metric (if you want to keep using it) ──
echo ""
echo "▸ [A] Creating log-based metric for HTTP 5xx (CORRECT filter):"
gcloud logging metrics create http5xx_errors_v2 \
  --description="Counts HTTP 5xx errors from Cloud Run incident-tester" \
  --log-filter='
    resource.type="cloud_run_revision"
    resource.labels.project_id="'"$PROJECT"'"
    resource.labels.service_name="'"$SERVICE"'"
    (textPayload=~"500" OR jsonPayload.code>=500)
    severity>=ERROR
  ' 2>/dev/null && echo "  ✓ Metric created" || echo "  (metric may already exist)"

echo ""
echo "▸ [A] Creating alerting policy for log-based 5xx metric:"
cat > /tmp/alert_5xx_log.json << 'ENDJSON'
{
  "displayName": "HTTP 5xx Errors (log-based) - Incident Tester",
  "combiner": "OR",
  "enabled": true,
  "conditions": [
    {
      "displayName": "5xx error count > 3 in 2 min",
      "conditionMatchedLog": {
        "filter": "resource.type=\"cloud_run_revision\" resource.labels.service_name=\"cloud-incident-tester\" (textPayload=~\"500\" OR jsonPayload.code>=500) severity>=ERROR"
      }
    }
  ],
  "alertStrategy": {
    "autoClose": "1800s"
  },
  "notificationChannels": []
}
ENDJSON
gcloud monitoring policies create --policy-from-file=/tmp/alert_5xx_log.json \
  --format="value(name)" 2>/dev/null && echo "  ✓ Log-based alert policy created" || echo "  (creation failed — check filter)"

# ── Option B: Built-in Cloud Run metric (RECOMMENDED) ──────────
echo ""
echo "▸ [B] Creating alerting policy for built-in request_count (RECOMMENDED):"
cat > /tmp/alert_5xx_builtin.json << ENDJSON
{
  "displayName": "HTTP 5xx Errors (built-in) - Incident Tester",
  "combiner": "OR",
  "enabled": true,
  "conditions": [
    {
      "displayName": "5xx response count > 3 in 2 min",
      "conditionThreshold": {
        "filter": "resource.type=\"cloud_run_revision\" AND resource.labels.project_id=\"${PROJECT}\" AND resource.labels.service_name=\"${SERVICE}\" AND metric.type=\"run.googleapis.com/request_count\" AND metric.label.response_code_class=\"5xx\"",
        "aggregation": {
          "alignmentPeriod": "120s",
          "perSeriesAligner": "ALIGN_COUNT",
          "crossSeriesReducer": "REDUCE_SUM",
          "groupByFields": [
            "resource.labels.service_name"
          ]
        },
        "comparison": "COMPARISON_GT",
        "thresholdValue": 3,
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
  "notificationChannels": []
}
ENDJSON
gcloud monitoring policies create --policy-from-file=/tmp/alert_5xx_builtin.json \
  --format="value(name)" 2>/dev/null && echo "  ✓ Built-in metric alert policy created" || echo "  (creation failed)"

# ── CPU alert ──────────────────────────────────────────────────
echo ""
echo "▸ [C] Creating alerting policy for CPU > 80%:"
cat > /tmp/alert_cpu.json << ENDJSON
{
  "displayName": "High CPU Usage - Incident Tester",
  "combiner": "OR",
  "enabled": true,
  "conditions": [
    {
      "displayName": "CPU utilization > 80%",
      "conditionThreshold": {
        "filter": "resource.type=\"cloud_run_revision\" AND resource.labels.project_id=\"${PROJECT}\" AND resource.labels.service_name=\"${SERVICE}\" AND metric.type=\"run.googleapis.com/container/cpu/utilization\"",
        "aggregation": {
          "alignmentPeriod": "120s",
          "perSeriesAligner": "ALIGN_MEAN",
          "crossSeriesReducer": "REDUCE_MEAN",
          "groupByFields": [
            "resource.labels.service_name"
          ]
        },
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
  "notificationChannels": []
}
ENDJSON
gcloud monitoring policies create --policy-from-file=/tmp/alert_cpu.json \
  --format="value(name)" 2>/dev/null && echo "  ✓ CPU alert policy created" || echo "  (creation failed)"

# ── Summary ────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════"
echo " Listing all alerting policies:"
echo "═══════════════════════════════════════════════════════════"
gcloud monitoring policies list --format="table(name,displayName,enabled)" 2>/dev/null

echo ""
echo "To test: inject errors with gcp_fire.py, then check:"
echo "  gcloud monitoring incidents list --format='table(name,displayName,state,openedAt)'"
echo ""
echo "═══════════════════════════════════════════════════════════"
