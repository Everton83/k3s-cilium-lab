# MiniStack e GitLab Runner são propositalmente NÃO recursos do Kubernetes
# (ver ../README.md) — são serviços nativos do host, instalados via
# local-exec chamando os scripts que também servem pra instalação manual.
# `linux_user` não tem sudo sem senha, então cada bloco autentica o sudo uma
# vez (`sudo -S -v`) no início do MESMO comando -- o cache de timestamp do
# sudo cobre as chamadas `sudo` simples dentro do script chamado em seguida,
# sem precisar reescrever os scripts pra pipar senha em cada linha.

resource "null_resource" "ministack" {
  count = var.install_ministack ? 1 : 0

  triggers = {
    script_sha = filemd5("${path.module}/../ministack/install.sh")
    unit_sha   = filemd5("${path.module}/../ministack/ministack.service")
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail
      echo "$SUDO_PASS" | sudo -S -v
      bash ${path.module}/../ministack/install.sh
    EOT
    environment = {
      SUDO_PASS = var.sudo_password
    }
  }
}

resource "null_resource" "gitlab_runner" {
  count = var.install_gitlab_runner ? 1 : 0

  triggers = {
    script_sha = filemd5("${path.module}/../gitlab-runner/install.sh")
    unit_sha   = filemd5("${path.module}/../gitlab-runner/gitlab-runner.service")
    # muda se o token/URL/descrição mudarem, força re-registrar
    token_sha = sha256(var.gitlab_runner_token)
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail
      echo "$SUDO_PASS" | sudo -S -v
      bash ${path.module}/../gitlab-runner/install.sh "$GITLAB_URL" "$RUNNER_TOKEN" "$RUNNER_DESCRIPTION"
    EOT
    environment = {
      SUDO_PASS          = var.sudo_password
      GITLAB_URL         = var.gitlab_url
      RUNNER_TOKEN       = var.gitlab_runner_token
      RUNNER_DESCRIPTION = var.gitlab_runner_description
    }
  }
}
