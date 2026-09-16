variable "kubeconfig_path" {
  description = "Caminho do kubeconfig do k3s no host onde este Terraform roda."
  type        = string
  default     = "/etc/rancher/k3s/k3s.yaml"
}

variable "node_ip" {
  description = <<-EOT
    IP do node k3s (também o IP do host, já que é single-node). Usado pra
    montar os hostnames *.nip.io do Gateway API e o endpoint do MiniStack.
  EOT
  type        = string
  default     = "192.168.3.200"
}

variable "linux_user" {
  description = "Usuário Linux local que vai rodar o MiniStack (pipx instala em $HOME/.local/bin dele)."
  type        = string
  default     = "batata"
}

variable "sudo_password" {
  description = <<-EOT
    Senha de sudo do linux_user. Necessária pros recursos host-level em
    host-services.tf (instalação do MiniStack e do GitLab Runner via
    null_resource + local-exec) — helm_release e kubernetes_* não precisam
    disso, falam direto com a API do k3s.

    Passe como variável de ambiente no momento do apply, nunca num arquivo
    versionado:
      TF_VAR_sudo_password='...' terraform apply
    Fica em texto plano no state local (os provisioners do Terraform não
    criptografam state) — aceitável aqui por ser uma máquina de laboratório
    de usuário único com state local, não um backend remoto compartilhado.
  EOT
  type        = string
  sensitive   = true
}

variable "argocd_admin_password" {
  description = <<-EOT
    Senha de admin do ArgoCD, aplicada via patch de hash bcrypt no Secret
    (ver argocd.tf) -- nunca em texto plano no cluster ou no histórico do
    shell. Deixe em branco ("") pra pular esse passo e usar a senha
    autogerada padrão do chart (visível em kubectl -n argocd get secret
    argocd-initial-admin-secret).
  EOT
  type        = string
  sensitive   = true
  default     = ""
}

variable "gitlab_url" {
  description = "URL da instância GitLab onde o runner será registrado."
  type        = string
  default     = "https://gitlab.com"
}

variable "gitlab_runner_token" {
  description = <<-EOT
    Runner authentication token (glrt-...) da página Settings > CI/CD >
    Runners > "New project runner" do projeto GitLab alvo. Passe via
    TF_VAR_gitlab_runner_token, nunca versionado.
  EOT
  type        = string
  sensitive   = true
}

variable "gitlab_runner_description" {
  description = "Descrição exibida pro runner na UI do GitLab."
  type        = string
  default     = "batata-server (nativo, executor shell no host)"
}

variable "install_ministack" {
  description = "Se true, instala o MiniStack no host via host-services.tf."
  type        = bool
  default     = true
}

variable "install_gitlab_runner" {
  description = "Se true, instala e registra o GitLab Runner no host via host-services.tf."
  type        = bool
  default     = true
}
