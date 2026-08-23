#!/usr/bin/env python3
"""
Cloud Incident Tester - A simple application designed to generate various types of 
events and errors that can be used to test cloud-native AI incident response agents.

This application simulates:
- Random HTTP errors (500, 503)
- Resource usage spikes
- Security-related events (failed logins)
- Application exceptions with stack traces
- Health check endpoints
- Configurable error rates via environment variables

Designed to be deployed on AWS, GCP, and Azure to test their respective 
AI-powered incident response agents.
"""

import os
import logging
import time

import random
import json
from datetime import datetime
from flask import Flask, jsonify, request


# ---- NEW: load .env if it exists ---------------------------------
from dotenv import load_dotenv
load_dotenv()   # populates os.environ with variables from a .env file

app = Flask(__name__)

# Configure logging to output to stdout (for container/cloud compatibility)
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s %(levelname)s %(name)s %(threadName)s : %(message)s',
    handlers=[
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# Configuration via environment variables with defaults
ERROR_RATE = float(os.environ.get('ERROR_RATE', '0.1'))  # 10% error rate by default
LOG_LEVEL = os.environ.get('LOG_LEVEL', 'INFO').upper()
ENABLE_RESOURCE_SPIKES = os.environ.get('ENABLE_RESOURCE_SPIKES', 'false').lower() == 'true'
SPIKE_DURATION = int(os.environ.get('SPIKE_DURATION', '300'))  

print(ERROR_RATE)
print(LOG_LEVEL)
print(ENABLE_RESOURCE_SPIKES)

# Set log level based on environment
logger.setLevel(getattr(logging, LOG_LEVEL, logging.INFO))

@app.route('/health')
def health():
    """Health check endpoint - should return 200 OK when healthy"""
    logger.info("Health check requested")
    return jsonify({"status": "healthy", "timestamp": datetime.utcnow().isoformat()}), 200

@app.route('/')
def home():
    """Home endpoint with occasional errors based on ERROR_RATE"""
    if random.random() < ERROR_RATE:
        logger.error("Simulated error in home endpoint - random failure")
        return jsonify({"error": "Internal server error", "code": 500}), 500
    else:
        logger.info("Home endpoint accessed successfully")
        return jsonify({"message": "Cloud Incident Tester is running!", "timestamp": datetime.utcnow().isoformat()})

@app.route('/api/data')
def get_data():
    """API endpoint that simulates database/API failures"""
    if random.random() < ERROR_RATE:
        logger.error("Database connection failed in /api/data")
        return jsonify({"error": "Service unavailable", "code": 503}), 503
    else:
        # Simulate some data processing
        data = {
            "id": random.randint(1, 1000),
            "value": round(random.random() * 100, 2),
            "timestamp": datetime.utcnow().isoformat(),
            "processed_by": "cloud-incident-tester"
        }
        logger.info(f"Data retrieved successfully: ID {data['id']}")
        return jsonify(data)

@app.route('/api/error/log')
def generate_error_log():
    """Endpoint that deliberately logs an error with full stack trace"""
    try:
        # Simulate a division by zero error
        result = 1 / 0
    except Exception as e:
        logger.exception("Exception occurred in /api/error/log - intentional error for testing")
        return jsonify({"error": "Intentional error logged", "code": 500, "type": "ZeroDivisionError"}), 500
    return jsonify({"message": "No error this time"}), 200

@app.route('/api/error/resource')
def resource_spike():
    """Simulate a resource usage spike (CPU‑intensive work) for SPIKE_DURATION seconds."""
    if not ENABLE_RESOURCE_SPIKES:
        return jsonify({"message": "Resource spikes disabled via ENABLE_RESOURCE_SPIKES=false"}), 200
    logger.warning(f"Starting resource spike simulation for {SPIKE_DURATION} seconds")
    start_time = time.time()
    # Busy‑wait loop – you can replace the inner work with anything that keeps the CPU busy.
    # Here we do a tiny bit of work each iteration so the loop isn’t a pure sleep,
    # but the dominant factor is the elapsed time.
    while time.time() - start_time < SPIKE_DURATION:
        # Light computation to keep the core occupied; adjust the range if you need more/less load.
        _ = sum(x * x for x in range(500))   # ~0.1 ms per iteration – mainly we just wait
    elapsed = time.time() - start_time
    logger.warning(f"Resource spike simulation completed after {elapsed:.2f} seconds")
    return jsonify({
        "message": "Resource spike simulation completed",
        "duration_seconds": round(elapsed, 2)
    }), 200

@app.route('/api/error/security')
def security_event():
    """Simulate a security-relevant event (failed login attempt)"""
    client_ip = request.remote_addr or 'unknown'
    logger.warning(f"SECURITY ALERT: Failed login attempt for user 'admin' from IP {client_ip}")
    logger.info(f"Security event: Account locked due to multiple failed attempts from {client_ip}")
    return jsonify({
        "message": "Security event logged", 
        "event_type": "failed_login",
        "user": "admin",
        "source_ip": client_ip,
        "timestamp": datetime.utcnow().isoformat()
    }), 200

@app.route('/api/info')
def app_info():
    """Return application information and configuration"""
    return jsonify({
        "application": "Cloud Incident Tester",
        "version": "1.0.0",
        "description": "Application designed to generate test incidents for cloud AI agent evaluation",
        "configuration": {
            "error_rate": ERROR_RATE,
            "log_level": LOG_LEVEL,
            "resource_spikes_enabled": ENABLE_RESOURCE_SPIKES
        },
        "endpoints": {
            "health": "GET /health",
            "home": "GET /",
            "api_data": "GET /api/data",
            "error_log": "GET /api/error/log",
            "resource_spike": "GET /api/error/resource",
            "security_event": "GET /api/error/security",
            "app_info": "GET /api/info"
        }
    })

if __name__ == '__main__':
    # Get port from environment (for cloud compatibility) or default to 5000
    port = int(os.environ.get('PORT', 5000))
    debug = os.environ.get('FLASK_DEBUG', 'false').lower() == 'true'
    
    logger.info(f"Starting Cloud Incident Tester on port {port}")
    logger.info(f"Configuration: ERROR_RATE={ERROR_RATE}, LOG_LEVEL={LOG_LEVEL}, ENABLE_RESOURCE_SPIKES={ENABLE_RESOURCE_SPIKES}")
    logger.info(f"Endpoints available: /health, /, /api/data, /api/error/log, /api/error/resource, /api/error/security, /api/info")
    
    app.run(host='0.0.0.0', port=port, debug=debug, use_reloader=False)