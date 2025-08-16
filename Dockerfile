# ---- Stage 1: Builder ----
FROM python:3.12-slim AS builder

# Install Python, pip, curl, gnupg for speedtest repo setup
RUN apt-get update && apt-get install -y \
    python3 python3-pip curl gnupg \
  && rm -rf /var/lib/apt/lists/*

# Add Ookla Speedtest CLI repository & install
RUN curl -s https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh | bash \
  && apt-get update && apt-get install -y speedtest \
  && rm -rf /var/lib/apt/lists/*

# Install Python dependencies into /install
COPY requirements.txt /tmp/
RUN pip install --no-cache-dir -r /tmp/requirements.txt

# Copy only necessary app source files
COPY main.py /app/main.py
COPY speedflux /app/speedflux

# Collect all shared libs required by speedtest
RUN mkdir -p /speedtest-libs && \
    ldd /usr/bin/speedtest | \
    awk '/=>/ { print $3 }' | \
    xargs -I '{}' cp -v '{}' /speedtest-libs/ || true

# # Fix permissions for OpenShift (root group ownership + group writable)
# RUN chown -R 0:0 /app && chmod -R g=u /app

# ---- Stage 2: Runtime ----
# Use debug non-root distroless variant for initial testing
# FROM gcr.io/distroless/python3-debian11-debug-nonroot
FROM gcr.io/distroless/python3-debian12:nonroot

# Switch to non-root user
USER 1001

# Copy the packages we need from our build container
COPY --from=builder /usr/local/lib/python3.12/site-packages /usr/local/lib/python3.12/site-packages

# Copy speedtest binary & required libs
COPY --from=builder /usr/bin/speedtest /usr/bin/
COPY --from=builder /speedtest-libs/ /usr/lib/

# Copy  app
COPY --from=builder --chown=1001:0 --chmod=775 /app /app

# Set environment variable so Python can find the packages we installed
ENV PYTHONPATH=/usr/local/lib/python3.12/site-packages

WORKDIR /app
CMD ["main.py"]
