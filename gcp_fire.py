#!/usr/bin/env python3
"""
GCP Fault Injection Script — Cloud Incident Tester
Mirrors azure_fire.py for the GCP leg of the cross-provider comparison.

Usage (from Cloud Shell or any machine with curl + python3):
    python3 gcp_fire.py https://cloud-incident-tester-132317288178.us-central1.run.app

Outputs:
    - Timestamped console log of every request
    - incident_responses.jsonl (same schema as Azure leg)
"""

import json
import sys
import time
import subprocess
import urllib.request
import urllib.error
from datetime import datetime, timezone

# ── Config ──────────────────────────────────────────────────────
BASE_URL = sys.argv[1] if len(sys.argv) > 1 else \
    "https://cloud-incident-tester-132317288178.us-central1.run.app"

HTTP_BURST_COUNT  = 25      # number of / requests (10% random errors each)
HTTP_BURST_DELAY  = 2       # seconds between requests (matches Azure spacing)
SPIKE_DURATION    = 60      # override SPIKE_DURATION via env to keep free-tier safe
SECURITY_COUNT    = 5       # security event injections
SECURITY_DELAY    = 5       # seconds between security events

OUTPUT_FILE = "incident_responses.jsonl"

# ── Helpers ─────────────────────────────────────────────────────
def utc_now():
    return datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")

def curl_get(url, timeout=360):
    """Return (http_code, response_body_str, elapsed_ms)."""
    start = time.monotonic()
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            body = resp.read().decode("utf-8", errors="replace")
            code = resp.status
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace") if e.fp else ""
        code = e.code
    except Exception as e:
        body = str(e)
        code = 0
    elapsed = int((time.monotonic() - start) * 1000)
    return code, body, elapsed

def log_record(label, endpoint, ts, http_code, duration_ms=0, response_body=""):
    rec = {
        "label": label,
        "endpoint": endpoint,
        "ts_utc": ts,
        "http_code": http_code,
        "duration_ms": duration_ms,
        "response_body": response_body[:500],
    }
    with open(OUTPUT_FILE, "a") as f:
        f.write(json.dumps(rec) + "\n")
    print(f"  [{label}] {endpoint} → HTTP {http_code} ({duration_ms}ms) @ {ts}")
    return rec

# ── Main ────────────────────────────────────────────────────────
def main():
    records = []
    print(f"=" * 60)
    print(f"GCP Fault Injection — {utc_now()}")
    print(f"Target: {BASE_URL}")
    print(f"=" * 60)

    # ── Phase 1: HTTP error burst ───────────────────────────────
    print(f"\n▸ Phase 1: HTTP error burst ({HTTP_BURST_COUNT} requests, {HTTP_BURST_DELAY}s spacing)")
    errors_seen = 0
    for i in range(1, HTTP_BURST_COUNT + 1):
        ts = utc_now()
        code, body, ms = curl_get(BASE_URL + "/")
        rec = log_record("http_error", "/", ts, code, ms, body)
        records.append(rec)
        if code >= 500:
            errors_seen += 1
        if i < HTTP_BURST_COUNT:
            time.sleep(HTTP_BURST_DELAY)
    print(f"  → {errors_seen}/{HTTP_BURST_COUNT} errors returned")

    # ── Phase 2: Deterministic 500 (error/log) ─────────────────
    print(f"\n▸ Phase 2: Deterministic error (3 × /api/error/log)")
    for i in range(1, 4):
        ts = utc_now()
        code, body, ms = curl_get(BASE_URL + "/api/error/log")
        records.append(log_record("error_log", "/api/error/log", ts, code, ms, body))
        time.sleep(1)

    # ── Phase 3: Resource spike ─────────────────────────────────
    print(f"\n▸ Phase 3: Resource spike (1 × /api/error/resource — may block)")
    ts = utc_now()
    code, body, ms = curl_get(BASE_URL + "/api/error/resource", timeout=400)
    records.append(log_record("resource_spike", "/api/error/resource", ts, code, ms, body))

    # ── Phase 4: Security events ────────────────────────────────
    print(f"\n▸ Phase 4: Security events ({SECURITY_COUNT} × /api/error/security)")
    for i in range(1, SECURITY_COUNT + 1):
        ts = utc_now()
        code, body, ms = curl_get(BASE_URL + "/api/error/security")
        records.append(log_record("security_event", "/api/error/security", ts, code, ms, body))
        if i < SECURITY_COUNT:
            time.sleep(SECURITY_DELAY)

    # ── Summary ─────────────────────────────────────────────────
    print(f"\n{'=' * 60}")
    print(f"Done — {len(records)} records written to {OUTPUT_FILE}")
    print(f"Errors (HTTP ≥500): {sum(1 for r in records if r['http_code'] >= 500)}")
    print(f"Security events:    {SECURITY_COUNT}")
    print(f"Resource spikes:    1")
    print(f"{'=' * 60}")

if __name__ == "__main__":
    main()
