#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────
# GCP Alerting Diagnostic — run in Cloud Shell
# Checks every link in the alert chain: logs → metric → policy → notification
# ──────────────────────────────────────────────────────────────────
set -euo pipefail

PROJECT=$(gcloud config get-value project 2>/dev/null)
echo "═══════════════════════════════════════════════════════════"
echo " GCP Alerting Diagnostic — project: $PROJECT"
echo "═══════════════════════════════════════════════════════════"

# ── 1. Are error logs actually landing in Cloud Logging? ────────
echo ""
echo "▸ [1/6] Checking Cloud Logging for error logs (last 10 min)..."
LOG_COUNT=$(gcloud logging read \
  'resource.type="cloud_run_revision" AND resource.labels.service_name="cloud-incident-tester" AND severity>=ERROR' \
  --limit=5 --format=json 2>/dev/null | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
echo "  Found $LOG_COUNT error-level log entries"
if [ "$LOG_COUNT" = "0" ]; then
  echo "  ⚠  No error logs found. The metric filter won't match anything."
  echo "  → Check Logging Explorer for the exact resource type and labels."
fi

# ── 2. Show actual log entries so we can verify the filter ──────
echo ""
echo "▸ [2/6] Sample error logs (to verify filter match):"
gcloud logging read \
  'resource.type="cloud_run_revision" AND resource.labels.service_name="cloud-incident-tester" AND severity>=ERROR' \
  --limit=3 --format=json 2>/dev/null | python3 -c "
import sys, json
entries = json.load(sys.stdin)
for e in entries:
    ts = e.get('timestamp','?')
    sev = e.get('severity','?')
    msg = e.get('textPayload','') or json.dumps(e.get('jsonPayload',''))[:120]
    print(f'  {ts} [{sev}] {msg}')
" 2>/dev/null || echo "  (could not parse logs)"

# ── 3. List all log-based metrics ──────────────────────────────
echo ""
echo "▸ [3/6] Log-based metrics in project:"
gcloud logging metrics list --format="table(name,metricDescriptor.type,description)" 2>/dev/null || echo "  (none found or API not enabled)"

# ── 4. Show the actual filter of each custom metric ────────────
echo ""
echo "▸ [4/6] Metric filter details (CRITICAL — this is usually the problem):"
for metric_name in $(gcloud logging metrics list --format="value(name)" 2>/dev/null); do
  echo ""
  echo "  Metric: $metric_name"
  gcloud logging metrics describe "$metric_name" --format=json 2>/dev/null | python3 -c "
import sys, json
d = json.load(sys.stdin)
filt = d.get('filter','')
desc = d.get('metricDescriptor',{})
print(f'    Type:       {desc.get(\"type\",\"?\")}')
print(f'    Kind:       {desc.get(\"metricKind\",\"?\")}')
print(f'    Value type: {desc.get(\"valueType\",\"?\")}')
print(f'    Filter:')
for line in filt.split('\n'):
    print(f'      {line}')
" 2>/dev/null
done

# ── 5. List all alerting policies ──────────────────────────────
echo ""
echo "▸ [5/6] Alerting policies:"
gcloud monitoring policies list --format="table(name,displayName,combiner,enabled)" 2>/dev/null || echo "  (none found)"

# ── 6. Show detailed policy conditions (the likely culprit) ────
echo ""
echo "▸ [6/6] Alerting policy details (CRITICAL):"
for policy_name in $(gcloud monitoring policies list --format="value(name)" 2>/dev/null); do
  echo ""
  echo "  Policy: $policy_name"
  gcloud monitoring policies describe "$policy_name" --format=json 2>/dev/null | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(f'    Display name: {d.get(\"displayName\",\"?\")}')
print(f'    Enabled:      {d.get(\"enabled\",\"?\")}')
print(f'    Combiner:     {d.get(\"combiner\",\"?\")}')
for c in d.get('conditions',[]):
    ct = c.get('conditionThreshold',{}) or c.get('conditionMatchedLog',{})
    print(f'    Condition: {c.get(\"displayName\",\"?\")}')
    filt = ct.get('filter','')
    print(f'      Filter: {filt[:200]}')
    if 'comparison' in ct:
        print(f'      Comparison:   {ct[\"comparison\"]}')
        print(f'      Threshold:    {ct.get(\"thresholdValue\",\"?\")}')
        print(f'      Duration:     {ct.get(\"duration\",\"?\")}')
    if 'aggregation' in ct:
        agg = ct['aggregation']
        print(f'      Aggregation:  {agg.get(\"alignmentPeriod\",\"?\")} / {agg.get(\"perSeriesAligner\",\"?\")} / {agg.get(\"crossSeriesReducer\",\"?\")}')
notifs = d.get('notificationChannels',[])
print(f'    Notification channels: {len(notifs)}')
if not notifs:
    print(f'    ⚠  NO notification channel — alerts fire but go nowhere visible!')
for n in notifs:
    print(f'      → {n}')
" 2>/dev/null
done

# ── 7. Quick test: create a raw log count to verify metric works ─
echo ""
echo "═══════════════════════════════════════════════════════════"
echo " DIAGNOSIS SUMMARY"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "Common causes for 'metric shows errors but alert never fires':"
echo ""
echo "  1. METRIC FILTER MISMATCH"
echo "     The log-based metric filter doesn't match actual log entries."
echo "     → Fix: update the metric filter to match the log structure above."
echo ""
echo "  2. WRONG METRIC TYPE IN ALERTING POLICY"
echo "     Policy references logging.googleapis.com/user/<name> but metric"
echo "     uses a different type. Or it uses run.googleapis.com/request_count"
echo "     (built-in) instead of the custom log metric."
echo "     → Fix: ensure policy condition filter matches the metric type exactly."
echo ""
echo "  3. NO NOTIFICATION CHANNEL"
echo "     Policy fires but has no channel → silent. You'll only see it in"
echo "     Monitoring → Alerting → Incidents if you check manually."
echo "     → Fix: add an email or Slack notification channel."
echo ""
echo "  4. ALIGNMENT / AGGREGATION MISMATCH"
echo "     Log-based counter metrics need ALIGN_COUNT aligner."
echo "     Wrong aligner = metric evaluates to 0 = no breach."
echo "     → Fix: set perSeriesAligner=ALIGN_COUNT, crossSeriesReducer=REDUCE_SUM."
echo ""
echo "  5. DURATION TOO LONG"
echo "     5-min duration means 5 min of sustained breach needed."
echo "     Short burst won't trigger. Reduce to 60s for testing."
echo "     → Fix: set duration to 60s or 120s during experiments."
echo ""
echo "═══════════════════════════════════════════════════════════"
