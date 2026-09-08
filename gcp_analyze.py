#!/usr/bin/env python3
"""
GCP Evidence Analyzer — parses collected JSON and produces a summary.
Run after gcp_collect_evidence.sh.

Usage:
    python3 gcp_analyze.py [session_dir]
    # defaults to research/evidence/gcp/session-YYYY-MM-DD/
"""

import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

def load_json(path):
    try:
        with open(path) as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return None

def utc_now():
    return datetime.now(timezone.utc).strftime("%Y-%m-%d")

def analyze(session_dir):
    print(f"═══════════════════════════════════════════════════════════")
    print(f" GCP Experiment Analysis — {session_dir}")
    print(f"═══════════════════════════════════════════════════════════\n")

    # ── Fault injection records ────────────────────────────────
    jsonl_path = os.path.join(session_dir, "raw", "incident_responses.jsonl")
    records = []
    if os.path.exists(jsonl_path):
        with open(jsonl_path) as f:
            records = [json.loads(line) for line in f if line.strip()]
        print(f"▸ Fault injection: {len(records)} records")
        by_label = {}
        for r in records:
            lbl = r.get("label", "unknown")
            by_label.setdefault(lbl, []).append(r)
        for lbl, recs in by_label.items():
            codes = [r.get("http_code", 0) for r in recs]
            errors = sum(1 for c in codes if c >= 500)
            print(f"    {lbl}: {len(recs)} requests, {errors} errors (HTTP ≥500)")
        if records:
            first = records[0].get("ts_utc", "?")
            last = records[-1].get("ts_utc", "?")
            print(f"    Time span: {first} → {last}")
    else:
        print(f"▸ Fault injection: no incident_responses.jsonl found")

    # ── Cloud Run logs ─────────────────────────────────────────
    print()
    logs = load_json(os.path.join(session_dir, "raw", "cloud_run_logs.json"))
    if logs is not None:
        print(f"▸ Cloud Run logs: {len(logs)} entries")
        errors = [l for l in logs if l.get("severity") in ("ERROR", "CRITICAL")]
        warnings = [l for l in logs if l.get("severity") == "WARNING"]
        print(f"    Errors:   {len(errors)}")
        print(f"    Warnings: {len(warnings)}")
        if errors:
            print(f"    First error: {errors[0].get('timestamp','?')}")
            print(f"    Last error:  {errors[-1].get('timestamp','?')}")
    else:
        print(f"▸ Cloud Run logs: not found")

    # ── Error logs ─────────────────────────────────────────────
    print()
    err_logs = load_json(os.path.join(session_dir, "raw", "error_logs.json"))
    if err_logs is not None:
        print(f"▸ Error-level logs: {len(err_logs)} entries")
        for entry in err_logs[:5]:
            ts = entry.get("timestamp", "?")
            text = entry.get("textPayload", "")[:100]
            print(f"    {ts}: {text}")
    else:
        print(f"▸ Error logs: not found")

    # ── SCC findings ───────────────────────────────────────────
    print()
    scc = load_json(os.path.join(session_dir, "raw", "scc_findings.json"))
    if scc is not None:
        print(f"▸ SCC findings: {len(scc)} findings")
        cats = {}
        for f in scc:
            cat = f.get("category", "?")
            cats[cat] = cats.get(cat, 0) + 1
        for cat, count in sorted(cats.items(), key=lambda x: -x[1]):
            print(f"    {cat}: {count}")
    else:
        print(f"▸ SCC findings: not available (no org or SCC not enabled)")

    # ── Monitoring incidents ───────────────────────────────────
    print()
    incidents = load_json(os.path.join(session_dir, "raw", "monitoring_incidents.json"))
    if incidents is not None:
        print(f"▸ Monitoring incidents: {len(incidents)}")
        for inc in incidents[:5]:
            name = inc.get("name", "?")
            state = inc.get("state", "?")
            policy = inc.get("conditionPolicyLabels", ["?"])[0] if inc.get("conditionPolicyLabels") else "?"
            opened = inc.get("openedAt", "?")
            print(f"    [{state}] {name} — opened {opened}")
    else:
        print(f"▸ Monitoring incidents: not available")

    # ── Alerting policies ──────────────────────────────────────
    print()
    policies = load_json(os.path.join(session_dir, "raw", "alerting_policies.json"))
    if policies is not None:
        print(f"▸ Alerting policies: {len(policies)}")
        for p in policies:
            name = p.get("displayName", "?")
            enabled = p.get("enabled", "?")
            combiner = p.get("combiner", "?")
            conds = p.get("conditions", [])
            print(f"    {name} — enabled={enabled}, combiner={combiner}, conditions={len(conds)}")
    else:
        print(f"▸ Alerting policies: not found")

    # ── Timeline estimate ──────────────────────────────────────
    print(f"\n{'═' * 59}")
    print(f" Timeline Estimate (if fault injection + logs available)")
    print(f"{'═' * 59}")
    if records and err_logs:
        fault_start = records[0].get("ts_utc", "")
        log_errors = [l for l in err_logs if l.get("severity") in ("ERROR", "CRITICAL")]
        if fault_start and log_errors:
            log_first = log_errors[0].get("timestamp", "")
            print(f"  Fault start:      {fault_start}")
            print(f"  First log error:  {log_first}")
            print(f"  → Detection latency: check timestamps above")
        else:
            print(f"  Insufficient data for timeline calculation")
    else:
        print(f"  Need both incident_responses.jsonl and error logs")

    print(f"\n{'═' * 59}")
    print(f" Next steps:")
    print(f"  1. Review SCC findings for AI Workbench investigation traces")
    print(f"  2. Check Monitoring → Alerting → Incidents for fired alerts")
    print(f"  3. Compare detection latency with Azure (~4.5 min fault→alert)")
    print(f"{'═' * 59}")

if __name__ == "__main__":
    if len(sys.argv) > 1:
        d = sys.argv[1]
    else:
        d = f"research/evidence/gcp/session-{utc_now()}"
    analyze(d)
