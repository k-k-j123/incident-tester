# Google Cloud Security AI Workbench (Sec-PaLM powered) Experiment - Detailed Broken Down Steps

This document provides a step-by-step breakdown for conducting your GCP experiment, mirroring the approach used for Azure as documented in KNOWLEDGE_TRANSFER.md.

## Phase 0: Preparation

### Step 0.1: Review Azure Documentation for Reference
Before starting, review the Azure process documented in:
- `KNOWLEDGE_TRANSFER.md` (Sections 22-40: Azure environment and progress)
- `research/azure_report.md` (findings written up)

### Step 0.2: Understand the Experiment Goal
Following the research plan, we aim to:
1. Deploy the Cloud Incident Tester application on GCP
2. Inject controlled faults (HTTP errors, resource spikes, security events)
3. Measure how Google Cloud Security AI Workbench (Sec-PaLM powered) detects, investigates, diagnoses, and resolves incidents
4. Compare results with AWS and Azure legs

## Phase 1: Environment Setup (Mirroring Azure Steps 1-2)

### Step 1.1: Create GCP Project (Equivalent to Azure Subscription/Resource Group)
```bash
# Set variables
PROJECT_ID="incident-responder-gcp-$(date +%s)"
REGION="us-central1"

# Create project
gcloud projects create $PROJECT_ID --name="Incident Response Research - GCP"

# Set as default project
gcloud config set project $PROJECT_ID

# Link billing account (you'll need to do this manually in console or have it set up)
# gcloud beta billing projects link $PROJECT_ID --billing-account=YOUR_BILLING_ACCOUNT
```

### Step 1.2: Enable Required APIs (Equivalent to Azure Resource Creation)
```bash
# Enable core APIs
gcloud services enable \
  cloudresourcemanager.googleapis.com \
  cloudbuild.googleapis.com \
  containerregistry.googleapis.com \
  run.googleapis.com \
  monitoring.googleapis.com \
  logging.googleapis.com \
  errorreporting.googleapis.com

# Enable security-specific APIs
gcloud services enable \
  securitycenter.googleapis.com \
  securityaiworkbench.googleapis.com \
  chronicle.googleapis.com \
  aiplatform.googleapis.com  # Required for Sec-PaLM access
```

### Step 1.3: Set Up Authentication and Service Account (Similar to Azure Cloud Shell)
```bash
# Get your user email for reference
USER_EMAIL=$(gcloud config get-value account)
echo "Authenticated as: $USER_EMAIL"

# Create service account for the experiment (similar to how Azure used managed identity)
gcloud iam service-accounts create incident-tester-sa \
  --display-name="Incident Tester Service Account"

# Grant necessary roles (equivalent to Azure Monitor/Leg Analytics permissions)
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:incident-tester-sa@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/monitoring.admin"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:incident-tester-sa@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/logging.admin"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:incident-tester-sa@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/securitycenter.admin"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:incident-tester-sa@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/aiplatform.user"  # For Sec-PaLM access

# Get service account key for local testing if needed
# gcloud iam service-accounts keys create key.json \
#   --iam-account=incident-tester-sa@$PROJECT_ID.iam.gserviceaccount.com
```

## Phase 2: Deploy Test Application (Mirroring Azure Steps 1-2 cont.)

### Step 2.1: Prepare the Cloud Incident Tester Application
```bash
# Navigate to testapp directory
cd /home/kaushik/Downloads/RP/testapp

# Verify the application files are present
ls -la
# Should see: cloud_incident_tester.py, Dockerfile, requirements.txt, .env, etc.
```

### Step 2.2: Build and Push Docker Image (Similar to Azure Container Apps)
```bash
# Configure Docker to authenticate with GCR
gcloud auth configure-docker

# Build the Docker image
docker build -t gcr.io/$PROJECT_ID/cloud-incident-tester:latest .

# Push to Google Container Registry
docker push gcr.io/$PROJECT_ID/cloud-incident-tester:latest

# Verify image was pushed
gcloud container images list --repository=gcr.io/$PROJECT_ID
```

### Step 2.3: Deploy to Cloud Run (Equivalent to Azure Container Apps)
```bash
# Deploy the application to Cloud Run
CLOUD_RUN_URL=$(gcloud run deploy incident-tester \
  --image=gcr.io/$PROJECT_ID/cloud-incident-tester:latest \
  --platform=managed \
  --region=$REGION \
  --allow-unauthenticated \
  --set-env-vars="ERROR_RATE=0.1,LOG_LEVEL=INFO,ENABLE_RESOURCE_SPIKES=true,SPIKE_DURATION=300" \
  --format="value(status.url)")

echo "Deployed to: $CLOUD_RUN_URL"
```

### Step 2.4: Verify Deployment (Equivalent to Azure URL Verification)
```bash
# Test the health endpoint
curl -s $CLOUD_RUN_URL/health | jq .

# Test the info endpoint to verify configuration
curl -s $CLOUD_RUN_URL/api/info | jq .
```

## Phase 3: Configure Monitoring and Alerting (Mirroring Azure Steps 28-33)

### Step 3.1: Create Log-Based Metrics for HTTP 5xx Errors (Like alert-http5xx)
```bash
# Create a log-based metric for 5xx errors
gcloud logging metrics create http5xx_errors \
  --description="Counts HTTP 5xx errors from incident tester" \
  --log-filter="resource.type=\"cloud_run_revision\" \
    resource.labels.service_name=\"incident-tester\" \
    severity>=ERROR \
    jsonPayload.code>=500"
```

### Step 3.2: Create Alert Policy for HTTP 5xx Errors (Like alert-http5xx)
```bash
# Create alert policy (equivalent to Azure's alert-http5xx)
ALERT_POLICY_ID=$(gcloud monitoring policies create \
  --display-name="HTTP 5xx Errors - Incident Tester" \
  --conditions="displayName=High HTTP 5xx Error Rate,conditionThreshold.filter=resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"incident-tester\" AND metric.type=\"logging.googleapis.com/user/http5xx_errors\",conditionThreshold.comparison=COMPARISON_GT,conditionThreshold.thresholdValue=5,conditionThreshold.duration=300s,conditionThreshold.trigger.count=1" \
  --alert-strategy="autoClose=3600s" \
  --combiner=OR \
  --format="value(name)")

echo "Created alert policy: $ALERT_POLICY_ID"
```

### Step 3.3: Create Log-Based Metric for CPU Usage (Like alert-cpu-high)
```bash
# Note: Cloud Run provides CPU utilization metrics natively
# We'll use the built-in metric instead of creating a log-based one
```

### Step 3.4: Create Alert Policy for High CPU Usage (Like alert-cpu-high)
```bash
# Create alert policy for CPU usage
CPU_ALERT_POLICY_ID=$(gcloud monitoring policies create \
  --display-name="High CPU Usage - Incident Tester" \
  --conditions="displayName=CPU Usage Above Threshold,conditionThreshold.filter=resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"incident-tester\" AND metric.type=\"run.googleapis.com/container/cpu/utilization\",conditionThreshold.comparison=COMPARISON_GT,conditionThreshold.thresholdValue=0.8,conditionThreshold.duration=300s,conditionThreshold.trigger.count=1" \
  --alert-strategy="autoClose=3600s" \
  --combiner=OR \
  --format="value(name)")

echo "Created CPU alert policy: $CPU_ALERT_POLICY_ID"
```

## Phase 4: Enable Security AI Workbench and Configure Investigation (New for GCP)

### Step 4.1: Verify Security AI Workbench is Enabled
```bash
# Check if Security AI Workbench API is enabled
gcloud services list --enabled | grep securityaiworkbench

# If not, enable it
gcloud services enable securityaiworkbench.googleapis.com
```

### Step 4.2: Configure Security Command Center for AI-Powered Analysis
```bash
# Ensure Security Command Center is enabled and configured
gcloud services enable securitycenter.googleapis.com

# Security Command Center should automatically analyze findings with AI
# Verify it's collecting data from Cloud Run
sleep 30  # Allow time for initial data collection

# Check for any findings
gcloud scc findings list --organization=$(gcloud organizations list --format="value(name)") \
  --limit=5 --format="value(finding.category,findings.state)"
```

### Step 4.3: Configure Sec-PaLM for Investigation Enhancement
```bash
# Vertex AI should already be enabled from Step 1.2
# Grant the service account access to use Sec-PaLM models
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:incident-tester-sa@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/aiplatform.admin"

# Optional: Create a dedicated key for AI Workbench if needed for API access
```

## Phase 5: Execute Fault Injection and Monitoring (Mirroring Azure Steps 40-44)

### Step 5.1: Establish Baseline and Test Endpoints
```bash
# Verify application is responding
echo "Testing endpoints..."
curl -s $CLOUD_RUN_URL/health
curl -s $CLOUD_RUN_URL/
curl -s $CLOUD_RUN_URL/api/info | jq '.configuration'
```

### Step 5.2: Execute HTTP Error Injection Test (Equivalent to Azure fault injection)
```bash
# Inject HTTP errors and log responses (similar to Azure's azure_fire.py)
echo "Starting HTTP error injection test..."
for i in {1..25}; do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" $CLOUD_RUN_URL/)
  TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  echo "{\"label\":\"http_error\",\"endpoint\":\"/\",\"ts_utc\":\"$TIMESTAMP\",\"http_code\":$STATUS}" >> incident_responses.jsonl
  echo "Request $i: HTTP $STATUS"
  sleep 2  # Space out requests like Azure did
done
```

### Step 5.3: Execute Resource Spike Injection Test
```bash
# Trigger resource spike (will block for SPIKE_DURATION seconds)
echo "Starting resource spike injection..."
START_TIME=$(date +%s)
RESPONSE=$(curl -s $CLOUD_RUN_URL/api/error/resource)
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
echo "{\"label\":\"resource_spike\",\"endpoint\":\"/api/error/resource\",\"ts_utc\":\"$TIMESTAMP\",\"http_code\":200,\"duration_ms\":$((DURATION * 1000))}" >> incident_responses.jsonl
echo "Resource spike completed in $DURATION seconds"
echo "Response: $RESPONSE"
```

### Step 5.4: Execute Security Event Injection Test
```bash
# Inject security events
echo "Starting security event injection..."
for i in {1..5}; do
  RESPONSE=$(curl -s $CLOUD_RUN_URL/api/error/security)
  TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  echo "{\"label\":\"security_event\",\"endpoint\":\"/api/error/security\",\"ts_utc\":\"$TIMESTAMP\",\"http_code\":200}" >> incident_responses.jsonl
  echo "Security event $i injected"
  sleep 5
done
```

## Phase 6: Measure Detection and Investigation (Mirroring Azure Steps 45-46)

### Step 6.1: Monitor for Alert Generation (Like Azure's alert-http5xx firing)
```bash
# Check monitoring for alert triggers
echo "Checking for alert notifications..."
sleep 30  # Wait for evaluation period

# In practice, you'd check alerting policy status or notification channels
# For now, we'll check if logs are being generated that would trigger alerts
gcloud logging read "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"incident-tester\" AND severity>=ERROR" \
  --limit=10 --format="json" > monitoring_check.json
```

### Step 6.2: Check Security Command Center for Findings (Initial Detection)
```bash
# Check for new findings in SCC (equivalent to Azure Monitor alerts)
echo "Checking Security Command Center for findings..."
BEFORE_TIME=$(date -u -d '5 minutes ago' +"%Y-%m-%dT%H:%M:%SZ")
sleep 60  # Wait for processing

# Query for findings after our test started
gcloud scc findings list \
  --organization=$(gcloud organizations list --format="value(name)") \
  --filter="state=ACTIVE AND createTime>\""$BEFORE_TIME"\"" \
  --order-by="createTime desc" \
  --limit=20 \
  --format="json" > scc_initial_findings.json

echo "Found $(jq '. | length' scc_initial_findings.json) new findings"
```

### Step 6.3: Check for Security AI Workbench Investigation Initiation
```bash
# While direct access to AI Workbench investigations may require console,
# we can infer investigation activity from SCC findings evolution
echo "Checking for investigation indicators in findings..."
sleep 120  # Allow more time for AI processing

gcloud scc findings list \
  --organization=$(gcloud organizations list --format="value(name)") \
  --filter="state=ACTIVE AND createTime>\""$BEFORE_TIME"\"" \
  --order-by="createTime desc" \
  --limit=20 \
  --format="json" > scc_findings_after_wait.json

# Compare findings to see if any have been updated (indicating investigation)
DIFF_COUNT=$(diff <(jq -r '.[].name' scc_initial_findings.json | sort) \
              <(jq -r '.[].name' scc_findings_after_wait.json | sort) | wc -l)
echo "Findings changed during waiting period: $DIFF_COUNT"
```

## Phase 7: Test Autonomous Investigation Capability (Mirroring Azure Steps 47-54)

### Step 7.1: Understand the Key Discovery from Azure
From KNOWLEDGE_TRANSFER.md Section 47-49:
> "KEY DISCOVERY — response plan is required for autonomous triggering. With Azure Monitor connected and alerts firing, zero incidents were created. Adding a permissive response plan made the agent adopt the unresolved alert within ~1 min."

For GCP, we need to determine if Security AI Workbench requires similar explicit configuration for autonomous investigation.

### Step 7.2: Check for Autonomous Investigation Settings
```bash
# Research equivalent of "response plan" in GCP
# This may involve:
# 1. Security Command Center notification settings
# 2. Security AI Workbench auto-investigation configurations
# 3. Chronicle SOAR playbooks or equivalent

echo "Checking for auto-investigation configurations..."
# Check SCC notification configs
gcloud scc notifications list --organization=$(gcloud organizations list --format="value(name)")

# Check if there are any security health analytics modules enabled
gcloud scc settings describe --organization=$(gcloud organizations list --format="value(name)")
```

### Step 7.3: Test Autonomous Mode (If Capable)
```bash
# If we discover that GCP Security AI Workbench can auto-investigate:
# 1. Ensure proper notification/investigation settings are configured
# 2. Inject faults without manual prompting
# 3. Measure time from alert to incident creation
# 4. Document the investigation process

echo "Setting up for autonomous test (if applicable)..."
# This step will depend on what we discover about GCP's autonomous capabilities
```

### Step 7.4: Measure Investigation Timelines (Like Azure's Metrics)
```bash
# Record timestamps for analysis
INJECTION_COMPLETE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
echo "Fault injection completed at: $INJECTION_COMPLETE"

# We'll analyze the collected data later to determine:
# - Fault → alert time
# - Alert → incident pickup time (if autonomous)
# - Investigation wall-clock time
# - Human interventions required
```

## Phase 8: Data Collection and Evidence (Mirroring Azure Steps 55-63)

### Step 8.1: Structured Evidence Collection (Like Azure's evidence convention)
```bash
# Create evidence directory structure
TIMESTAMP_DATE=$(date +%Y-%m-%d)
EVIDENCE_DIR="research/evidence/gcp/session-$TIMESTAMP_DATE"
mkdir -p $EVIDENCE_DIR/{raw,analysis}

# Copy incident responses
cp incident_responses.jsonl $EVIDENCE_DIR/raw/

# Collect raw logs and metrics
echo "Collecting raw data..."

# Cloud Run logs
gcloud logging read "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"incident-tester\"" \
  --format="json" --limit 5000 > $EVIDENCE_DIR/raw/cloud_run_logs.json

# Security Command Center findings
gcloud scc findings list --organization=$(gcloud organizations list --format="value(name)") \
  --format="json" > $EVIDENCE_DIR/raw/scc_findings.json

# Monitoring metrics (request counts)
gcloud monitoring read --project=$PROJECT_ID \
  --interval="$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ)/$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --filter='metric.type="run.googleapis.com/request_count"' \
  --format="json" > $EVIDENCE_DIR/raw/request_metrics.json

# Monitoring metrics (CPU utilization)
gcloud monitoring read --project=$PROJECT_ID \
  --interval="$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ)/$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --filter='metric.type="run.googleapis.com/container/cpu/utilization"' \
  --format="json" > $EVIDENCE_DIR/raw/cpu_metrics.json

# Log-based metric for HTTP 5xx errors
gcloud monitoring read --project=$PROJECT_ID \
  --interval="$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ)/$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --filter='metric.type="logging.googleapis.com/user/http5xx_errors"' \
  --format="json" > $EVIDENCE_DIR/raw/http5xx_metrics.json
```

### Step 8.2: Attempt to Get Security AI Workbench Traces (Like Azure's AppInsights)
```bash
# While direct trace access may not be available via CLI,
# we can check if there are any audit logs or exported data
echo "Checking for AI Workbench trace/data availability..."

# Check for any exported security data
# This would depend on GCP's specific export mechanisms for AI Workbench
# For now, we'll note this as a limitation to be addressed in manual investigation
echo "NOTE: Direct access to Security AI Workbench internal traces may require"
echo "manual investigation via Google Cloud Console or specific export configurations."
echo "See investigation_summary.md for documentation of observed behaviors."
```

### Step 8.3: Create Investigation Summary
```bash
# Create initial investigation summary
cat > $EVIDENCE_DIR/analysis/investigation_summary.md << EOF
# GCP Security AI Workbench Investigation Summary
**Date:** $(date)
**Project ID:** $PROJECT_ID
**Cloud Run URL:** $CLOUD_RUN_URL

## Fault Injection Summary
- Total HTTP error requests: 25
- Resource spike injections: 1
- Security event injections: 5
- See raw/incident_responses.jsonl for details

## Detection Timeline
- Fault injection start: [TO BE FILLED FROM LOGS]
- First error detected: [TO BE FILLED]
- Alert generated: [TO BE FILLED FROM MONITORING/SCC]

## Investigation Process
- Time to alert: [TO BE CALCULATED]
- Alert to investigation start: [TO BE CALCULATED]
- Investigation duration: [TO BE CALCULATED]
- Autonomous triggering: [YES/NO - TO BE DETERMINED]
- Human interventions required: [COUNT - TO BE DETERMINED]

## Findings
- Number of SCC findings generated: [TO BE COUNTED]
- Types of findings: [TO BE ANALYZED]
- Investigation depth: [TO BE ASSESSED]
- Remediation recommendations: [TO BE COLLECTED]

## Comparison to Azure
[TO BE COMPLETED AFTER AZURE RESULTS REVIEW]
EOF

echo "Investigation summary initialized at $EVIDENCE_DIR/analysis/investigation_summary.md"
```

## Phase 9: Resilience and Governance Testing (Mirroring Azure Steps 57-59)

### Step 9.1: Test Self-Recovery from Transient Errors
```bash
# While we can't directly inject errors into the AI agent like Azure did,
# we can observe if the investigation process handles transient data issues
echo "Checking for resilience indicators in findings..."

# Look for findings that show error states and subsequent recovery
# This would require manual analysis of the SCC findings over time
```

### Step 9.2: Check for Governance and Authorization Events
```bash
# Check audit logs for any security-relevant actions taken by the AI agent
# This would be equivalent to Azure's "Medium-risk write (alert changestate POST)"
echo "Checking audit logs for AI agent actions..."
gcloud logging read \
  'protoPayload.serviceName="securitycenter.googleapis.com"' \
  --limit=20 --format="json" > $EVIDENCE_DIR/raw/security_audit.json || echo "No security audit logs found or accessible"
```

## Phase 10: Cleanup and Iteration (Mirroring Azure Steps 77-88)

### Step 10.1: Prepare for Clean-Room Testing (Like Azure Step 77-80)
```bash
# For uncontaminated testing (CPU-spike clean-room run):
# 1. Delete and recreate Cloud Run service
# 2. Recreate alert policies and log-based metrics
# 3. Clear previous findings (if possible via SCC mute or similar)
# 4. Ensure no prior context influences investigation

echo "Setting up for clean-room test..."
# Delete current service
gcloud run services delete incident-tester --platform=managed --region=$REGION --quiet

# Optional: Delete alert policies (would need to capture IDs from earlier)
# gcloud monitoring policies delete $ALERT_POLICY_ID
# gcloud monitoring policies delete $CPU_ALERT_POLICY_ID

# Re-deploy for clean test
# [Repeat deployment steps with fresh configuration]
```

### Step 10.2: Plan for Remaining Experiment Types
```bash
# From KNOWLEDGE_TRANSFER.md Yet to do section:
# 1. CPU-spike clean-room run (GCP) - completed above framework
# 2. Security-event class - need alert rule for security events (create log-based metric for SECURITY lines)
# 3. AWS leg - [Separate process]
# 4. Neutral-prompt variant - re-run diagnosis without disclosing ground truth
# 5. Write-up - follow research_plan.md structure

echo "Next steps for GCP experimentation:"
echo "1. Create log-based metric for security events"
echo "2. Create alert policy for security events"
echo "3. Run clean-room CPU spike test"
echo "4. Run security event testing"
echo "5. Conduct neutral-prompt variant testing"
echo "6. Document findings for cross-provider comparison"
```

## Summary of Key Differences from Azure Approach

| Aspect | Azure Approach | GCP Approach (This Guide) |
|--------|----------------|---------------------------|
| **Compute** | Azure Container Apps | Google Cloud Run |
| **Monitoring** | Azure Monitor + Log Analytics | Cloud Monitoring + Cloud Logging |
| **Security Platform** | Azure Sentinel + Security Copilot | Security Command Center + Security AI Workbench (Sec-PaLM) |
| **SIEM** | Built-in to Sentinel | Chronicle (optional integration) |
| **Alert Creation** | Log query-based alert rules | Log-based metrics + alerting policies |
| **Autonomous Triggering** | Required response plan | To be determined (check AI Workbench configs) |
| **Evidence Collection** | JSONL logs + AppInsights traces | JSONL logs + SCC findings + Monitoring metrics |
| **Investigation Transcripts** | Thread-based in Console | Likely Console-based or via API exports |

## Important Notes for GCP Experiment

1. **Service Limitations**: Security AI Workbench may have regional restrictions or require allowlisting
2. **Cost Monitoring**: AI processing can incur significant costs - monitor usage closely
3. **Data Residue**: Confirm where investigation data is stored and processed for compliance
4. **Feature Availability**: Some AI capabilities may be in preview or have limited documentation
5. **Integration Points**: Security AI Workbench integrates with SCC, Chronicle, Mandiant Threat Intelligence, and VirusTotal - leverage these for richer context

## References for Further Research

- Security AI Workbench Documentation: https://cloud.google.com/security/ai-workbench
- Sec-PaLM Model Details: https://cloud.google.com/vertex-ai/docs/generative-ai/model-reference/sec-palm
- Security Command Center: https://cloud.google.com/security-command-center
- Chronicle SIEM: https://cloud.google.com/chronicle
- Cloud Run Documentation: https://cloud.google.com/run
- Cloud Monitoring Alerting: https://cloud.google.com/monitoring/alerts