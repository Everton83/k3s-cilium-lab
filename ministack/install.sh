#!/usr/bin/env bash
# Instala o MiniStack (github.com/ministackorg/ministack) como serviço nativo
# do host — deliberadamente NÃO como workload do k3s. Ver ../README.md pro
# porquê: o trabalho de um emulador local de AWS é ser uma dependência
# estável e rápida pro Terraform, não competir pelo orçamento apertado de
# memória do cluster.
#
# Mais ou menos idempotente: seguro reexecutar. Rode como o usuário alvo
# (não root), exceto onde o sudo aparece explicitamente.
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
curl -sf http://localhost:4566/_ministack/health && echo " | ministack saudável"
