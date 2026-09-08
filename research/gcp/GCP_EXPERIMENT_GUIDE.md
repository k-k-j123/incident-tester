# Google Cloud Security AI Workbench (Sec-PaLM powered) Experiment Guide

## Overview
This guide provides detailed, step-by-step instructions for conducting your experiment with Google Cloud Security AI Workbench (powered by Sec-PaLM) to test its incident response capabilities, following the same methodology used for the Azure leg of your research.

## Prerequisites
1. Google Cloud account with billing enabled
2. Google Cloud SDK installed and configured
3. Basic understanding of GCP security services
4. The Cloud Incident Tester application deployed and accessible

## Phase 1: Environment Setup

### Step 1: Enable Required APIs
```bash
# Enable Security AI Workbench API
gcloud services enable securityaiworkbench.googleapis.com

# Enable related security APIs
gcloud services enable securitycenter.googleapis.com
gcloud services enable chronicle.googleapis.com
gcloud services enable monitoring.googleapis.com
gcloud services enable logging.googleapis.com
```

### Step 2: Set Up Authentication
```bash
# Set your project ID
PROJECT_ID="your-gcp-project-id"
gcloud config set project $PROJECT_ID

# Ensure you're authenticated
gcloud auth application-default login
```

### Step 3: Create Service Account (if needed)
```bash
# Create service account for the experiment
gcloud iam service-accounts create incident-tester-sa \
    --display-name="Incident Tester Service Account"

# Grant necessary roles
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:incident-tester-sa@$PROJECT_ID.iam.gserviceaccount.com" \
    --role="roles/securitycenter.admin"

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:incident-tester-sa@$PROJECT_ID.iam.gserviceaccount.com" \
    --role="roles/monitoring.admin"

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:incident-tester-sa@$PROJECT_ID.iam.gserviceaccount.com" \
    --role="roles/logging.admin"
```

## Phase 2: Deploy Test Application

### Step 4: Prepare Cloud Incident Tester
Ensure you have the Cloud Incident Tester from `testapp/` directory ready for deployment.

### Step 5: Build and Push Docker Image
```bash
# Navigate to testapp directory
cd testapp

# Build Docker image
docker build -t gcr.io/$PROJECT_ID/cloud-incident-tester:latest .

# Configure Docker to use gcloud credentials
gcloud auth configure-docker

# Push to Google Container Registry
docker push gcr.io/$PROJECT_ID/cloud-incident-tester:latest
```

### Step 6: Deploy to Cloud Run (or GKE)
```bash
# Deploy to Cloud Run (simplest option)
gcloud run deploy incident-tester \
    --image gcr.io/$PROJECT_ID/cloud-incident-tester:latest \
    --platform managed \
    --region us-central1 \
    --allow-unauthenticated \
    --set-env-vars="ERROR_RATE=0.1,LOG_LEVEL=INFO,ENABLE_RESOURCE_SPIKES=true,SPIKE_DURATION=300"

# Note the URL provided after deployment
```

## Phase 3: Configure Security AI Workbench

### Step 7: Enable Security AI Workbench
```bash
# Enable the Security AI Workbench API if not already done
gcloud services enable securityaiworkbench.googleapis.com
```

### Step 8: Configure Sec-PaLM Access
```bash
# Enable Vertex AI API (required for Sec-PaLM)
gcloud services enable aiplatform.googleapis.com

# Grant necessary permissions to your service account for Vertex AI
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:incident-tester-sa@$PROJECT_ID.iam.gserviceaccount.com" \
    --role="roles/aiplatform.user"
```

### Step 9: Set Up Security Command Center Integration
```bash
# Enable Security Command Center if not already enabled
gcloud services enable securitycenter.googleapis.com

# Ensure Security Command Center is configured to collect logs from your deployed service
# This typically happens automatically when Cloud Run services are deployed
```

## Phase 4: Fault Injection and Monitoring

### Step 10: Establish Baseline Monitoring
Before injecting faults, verify your monitoring setup:
```bash
# Check if logs are being collected
gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=incident-tester" \
    --limit 10 --format json

# Check Security Command Center findings
gcloud scc findings list --organization=$(gcloud organizations list --format="value(name)") \
    --filter="state=ACTIVE" --limit 10
```

### Step 11: Create Alerting Policies
Create alerting policies similar to Azure's approach:
```bash
# Create alert policy for HTTP 5xx errors
gcloud monitoring policies create --policy-from-file=<(cat <<EOF
{
  "displayName": "HTTP 5xx Errors - Incident Tester",
  "combiner": "OR",
  "conditions": [
    {
      "displayName": "High HTTP 5xx Error Rate",
      "conditionThreshold": {
        "filter": "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"incident-tester\" AND metric.type=\"run.googleapis.com/request_count\" AND metric.label.\"response_code\">=500",
        "comparison": "COMPARISON_GT",
        "thresholdValue": 5.0,
        "duration": "300s",
        "trigger": {
          "count": 1
        }
      }
    }
  ],
  "alertStrategy": {
    "autoClose": "3600s"
  },
  "notificationChannels": []
}
EOF
)
```

### Step 12: Create Alert Policy for CPU Spikes
```bash
# Create alert policy for high CPU usage
gcloud monitoring policies create --policy-from-file=<(cat <<EOF
{
  "displayName": "High CPU Usage - Incident Tester",
  "combiner": "OR",
  "conditions": [
    {
      "displayName": "CPU Usage Above Threshold",
      "conditionThreshold": {
        "filter": "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"incident-tester\" AND metric.type=\"run.googleapis.com/container/cpu/utilization\"",
        "comparison": "COMPARISON_GT",
        "thresholdValue": 0.8,
        "duration": "300s",
        "trigger": {
          "count": 1
        }
      }
    }
  ],
  "alertStrategy": {
    "autoClose": "3600s"
  },
  "notificationChannels": []
}
EOF
)
```

## Phase 5: Conduct Experiments

### Step 13: HTTP Error Injection Test
```bash
# Inject HTTP errors and monitor response
for i in {1..20}; do
  curl -s -o /dev/null -w "%{http_code}\n" https://incident-tester-abc123-uc.a.run.app/
  sleep 2
done
```

### Step 14: Resource Spike Injection Test
```bash
# Trigger resource spike endpoint
curl -s https://incident-tester-abc123-uc.a.run.app/api/error/resource
# Note: This will block for SPIKE_DURATION seconds (default 300s)
```

### Step 15: Security Event Injection Test
```bash
# Inject security events
curl -s https://incident-tester-abc123-uc.a.run.app/api/error/security
```

## Phase 6: Investigate AI Agent Response

### Step 16: Monitor Security AI Workbench Response
After fault injection, monitor how the Security AI Workbench responds:
```bash
# Check for new findings in Security Command Center
gcloud scc findings list --organization=$(gcloud organizations list --format="value(name)") \
    --filter="state=ACTIVE AND createTime>\"$(date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%SZ)\"" \
    --order-by="createTime desc" --limit 20 --format json

# Check Security AI Workbench specific insights
# Note: Direct access to AI Workbench insights may require using the API or console
```

### Step 17: Analyze Investigation Results
Document the AI agent's response:
1. Time to detection
2. Investigation depth (root cause analysis)
3. Remediation recommendations
4. False positive/negative rates
5. Autonomous vs. prompted behavior

### Step 18: Test Autonomous Capabilities
To test autonomous triggering (similar to Azure's discovery):
1. Ensure alert policies are properly configured
2. Verify Security AI Workbench is set to auto-investigate
3. Inject faults without manual prompting
4. Measure time from alert to incident creation
5. Document investigation process

## Phase 7: Data Collection and Evidence

### Step 19: Structured Evidence Collection
Follow the evidence convention from Azure:
```
research/evidence/gcp/session-YYYY-MM-DD/
├── incident_responses.jsonl
├── raw/
│   ├── security_workbench_traces_*.csv
│   └── scc_findings_*.json
└── analysis/
    ├── investigation_summary.md
    └── metrics_calculated.json
```

### Step 20: Log Collection Script
Create a script to collect all relevant logs:
```bash
#!/bin/bash
DATE=$(date +%Y-%m-%d)
SESSION_DIR="research/evidence/gcp/session-$DATE"
mkdir -p $SESSION_DIR/raw $SESSION_DIR/analysis

# Collect Cloud Run logs
gcloud logging read "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"incident-tester\"" \
    --format="json" --limit 1000 > $SESSION_DIR/raw/cloud_run_logs.json

# Collect Security Command Center findings
gcloud scc findings list --organization=$(gcloud organizations list --format="value(name)") \
    --format="json" > $SESSION_DIR/raw/scc_findings.json

# Collect monitoring metrics
gcloud monitoring read --project=$PROJECT_ID \
    --interval="$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ)/$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --filter='metric.type="run.googleapis.com/request_count"' \
    --format="json" > $SESSION_DIR/raw/request_metrics.json
```

## Phase 8: Cleanup and Iteration

### Step 21: Resource Cleanup (if needed)
```bash
# Delete Cloud Run service
gcloud run services delete incident-tester --platform managed --region us-central1

# Delete alert policies (get policy IDs first)
# gcloud monitoring policies delete POLICY_ID

# Optional: Delete Docker image from Container Registry
# gcloud container images delete gcr.io/$PROJECT_ID/cloud-incident-tester:latest
```

### Step 22: Reset for Clean-Room Testing
For uncontaminated testing (similar to Azure's CPU-spike clean-room run):
1. Delete and recreate the Cloud Run service
2. Recreate alert policies
3. Clear previous findings (if possible)
4. Ensure no prior context influences the investigation

## References and Useful Commands

### Key GCP Security AI Workbench Resources
- Security AI Workbench Documentation: https://cloud.google.com/security/ai-workbench
- Sec-PaLM Details: https://cloud.google.com/vertex-ai/docs/generative-ai/model-reference/sec-palm
- Security Command Center: https://cloud.google.com/security-command-center
- Chronicle SIEM: https://cloud.google.com/chronicle

### Troubleshooting Commands
```bash
# Check service status
gcloud services list --enabled

# View logs for debugging
gcloud logging read "resource.type=\"cloud_run_revision\" AND severity>=ERROR" --limit 20

# Check IAM permissions
gcloud projects get-iam-policy $PROJECT_ID

# Monitor quota usage
gcloud compute quotas list --project=$PROJECT_ID
```

## Expected Outcomes and Metrics
Following the Azure experiment structure, aim to capture:

1. **Detection Latency**: Time from fault injection to alert generation
2. **Investigation Time**: Time from alert to root cause identification
3. **Autonomous Triggering**: Whether agent creates incidents without prompting
4. **Investigation Quality**: Accuracy of root cause analysis
5. **Remediation Effectiveness**: Quality and executability of recommendations
6. **False Positive Rate**: Incorrect alerts generated
7. **Tool Usage**: Number and types of API calls made by the AI agent
8. **Self-Healing Capability**: Ability to recover from transient errors

## Notes and Gotchas
- Security AI Workbench may require explicit enabling of investigation features
- Some AI capabilities may be in preview or require allowlisting
- Costs: Monitor usage as AI processing can incur charges
- Regional availability: Ensure Security AI Workbench is available in your chosen region
- Data residency: Confirm where investigation data is stored and processed