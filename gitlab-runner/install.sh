#!/usr/bin/env bash
# Instala um GitLab Runner nativo (executor shell) como serviço do host --
# deliberadamente NÃO um workload do k3s. Ver ../README.md: o consumo de
# recurso de um runner de CI é cheio de picos e imprevisível, exatamente o
# que um cluster com memória apertada não consegue absorver.
#
# Uso: ./install.sh <url-do-gitlab> <token-de-autenticacao-do-runner> [descricao]
#   <token-de-autenticacao-do-runner> é o token glrt-... da página
#   Settings > CI/CD > Runners > "New project runner" do projeto, NÃO o
#   fluxo antigo de registration-token compartilhado.
set -euo pipefail

GITLAB_URL="${1:?uso: install.sh <url-do-gitlab> <token-do-runner> [descricao]}"
RUNNER_TOKEN="${2:?uso: install.sh <url-do-gitlab> <token-do-runner> [descricao]}"
DESCRIPTION="${3:-$(hostname) (nativo, executor shell no host)}"

sudo curl -fsSL -o /usr/local/bin/gitlab-runner \
  "https://gitlab-runner-downloads.s3.amazonaws.com/v17.11.0/binaries/gitlab-runner-linux-amd64"
sudo chmod +x /usr/local/bin/gitlab-runner

# Fixado em v17.11.0 em vez da última versão: uma reprodução no mesmo dia
# contra a 19.3.3 mostrou falhas idênticas pro bug real que este script
# também corrige abaixo (não tem relação com a versão do runner), então a
# fixação é só "sabidamente funcional", não é algo essencial -- revisitar
# se houver motivo.

if ! id gitlab-runner &>/dev/null; then
  # Precisa de um shell de login DE VERDADE. O executor shell roda todo job
  # através de `bash -l`, então /usr/sbin/nologin aqui quebra todo job com um
  # "prepare environment: exit status 1" sem informação nenhuma -- ver a
  # correção abaixo pra a outra metade desta mesma classe de bug.
  sudo useradd --system --shell /bin/bash --home-dir /home/gitlab-runner --create-home gitlab-runner
fi

# A outra metade: o ~/.bash_logout padrão do Ubuntu chama `clear_console -q`
# em toda saída de shell de login pra limpar a tela "por privacidade". Sem
# um terminal controlador (sempre o caso em CI), o clear_console sai com
# código 1, e ESSE código vira o exit code do job inteiro -- independente do
# que o job em si fez. Corrigido só pra este usuário, não pro /etc/skel.
sudo -u gitlab-runner sed -i \
  's#\[ -x /usr/bin/clear_console \] && /usr/bin/clear_console -q$#[ -x /usr/bin/clear_console ] \&\& /usr/bin/clear_console -q || true#' \
  /home/gitlab-runner/.bash_logout

sudo install -m 644 "$(dirname "$0")/gitlab-runner.service" /etc/systemd/system/gitlab-runner.service
sudo systemctl daemon-reload
sudo systemctl enable gitlab-runner
sudo systemctl start gitlab-runner

sudo gitlab-runner register \
  --non-interactive \
  --url "$GITLAB_URL" \
  --token "$RUNNER_TOKEN" \
  --executor "shell" \
  --description "$DESCRIPTION"

sudo systemctl restart gitlab-runner
sudo systemctl status gitlab-runner --no-pager -l | head -8
