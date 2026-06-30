#!/usr/bin/env bash
# https://prometheus.io/docs/prometheus/latest/getting_started/
set -euo pipefail

# Keep this in sync with the path in prometheus.service
VERSION="3.5.4"
DIR="prometheus-${VERSION}.linux-amd64"
TARBALL="${DIR}.tar.gz"
INSTALL_DIR="$HOME/disk/${DIR}"
REPO_DIR="$HOME/data/AutoRouteServices"

cd ~/disk

# Download + extract only if not already installed (idempotent, avoids .1 .2 copies)
if [ ! -x "${INSTALL_DIR}/prometheus" ]; then
  wget -O "${TARBALL}" "https://github.com/prometheus/prometheus/releases/download/v${VERSION}/${TARBALL}"
  tar xvfz "${TARBALL}"
fi

# Always deploy our config (this is the step that was being missed)
cp "${REPO_DIR}/prometheus/prometheus.yml" "${INSTALL_DIR}/prometheus.yml"

# Validate before (re)starting so a bad config can't take the service down
"${INSTALL_DIR}/promtool" check config "${INSTALL_DIR}/prometheus.yml"

# Install / refresh the systemd unit
sudo cp "${REPO_DIR}/prometheus.service" /etc/systemd/system/
sudo systemctl daemon-reload

# If already running, hot-reload the config; otherwise start it
if systemctl is-active --quiet prometheus; then
  sudo systemctl reload prometheus || sudo systemctl restart prometheus
else
  sudo systemctl restart prometheus
fi

sudo systemctl status prometheus --no-pager
