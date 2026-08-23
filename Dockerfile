# --------------------------------------------------------------
# Dockerfile – Cloud Incident Tester
# --------------------------------------------------------------
FROM python:3.11-slim

# non‑root user
RUN groupadd -r appuser && useradd -r -g appuser appuser
WORKDIR /app

# install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

# copy application code
COPY cloud_incident_tester.py .

# (optional) copy .env so the loader can find it inside the image
# If you prefer to pass variables at run‑time you can omit this line.
COPY .env .

# fix permissions for non‑root user
RUN chown -R appuser:appuser /app
USER appuser

EXPOSE 5000

# default values (can be overridden at run‑time)
ENV ERROR_RATE=0.4 \
    LOG_LEVEL=INFO \
    ENABLE_RESOURCE_SPIKES=true \
    PORT=5000 \
    FLASK_APP=cloud_incident_tester.py \
    FLASK_RUN_HOST=0.0.0.0 \
    SPIKE_DURATION=300

# ---- FIXED CMD -------------------------------------------------
# Use shell form so ${PORT} (or $PORT) is expanded to the actual value.
CMD flask run --port=$PORT
# --------------------------------------------------------------