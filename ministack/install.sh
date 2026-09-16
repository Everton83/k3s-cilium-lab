#!/usr/bin/env bash
# Installs MiniStack (github.com/ministackorg/ministack) as a native host
# service — deliberately NOT a k3s workload. See ../README.md for why: a
# local AWS emulator's job is to be a stable, fast dependency for Terraform
# runs, not something competing for the cluster's own tight memory budget.
#
# Idempotent-ish: safe to re-run. Run as the target user (not root) except
# where sudo is shown explicitly.
set -euo pipefail

if ! command -v pipx >/dev/null; then
  sudo apt-get install -y pipx
  pipx ensurepath
fi

pipx install ministack

sudo install -m 644 "$(dirname "$0")/ministack.service" /etc/systemd/system/ministack.service
sudo systemctl daemon-reload
sudo systemctl enable --now ministack

sleep 1
curl -sf http://localhost:4566/_ministack/health && echo " | ministack healthy"
