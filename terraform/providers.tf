# Roda NO próprio servidor alvo (não numa máquina remota) — é o único lugar
# com acesso direto tanto à API do k3s (kubeconfig local, sem precisar de
# port-forward/VPN) quanto ao host em si (pra instalar MiniStack e o
# GitLab Runner via null_resource + local-exec em host-services.tf).
# O k3s.yaml costuma ser world-readable (0644), sem precisar de sudo pra ler.

provider "kubernetes" {
  config_path = var.kubeconfig_path
}

provider "helm" {
  kubernetes {
    config_path = var.kubeconfig_path
  }
}
