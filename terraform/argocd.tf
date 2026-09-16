resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "10.9.0"
  namespace        = "argocd"
  create_namespace = true

  values = [file("${path.module}/../argocd/values-batata.yaml")]

  depends_on = [helm_release.cilium] # precisa dos CRDs de Gateway API que o Cilium instala
}

# Define a senha de admin sem nunca colocá-la em texto plano num
# `helm install --set` (ficaria no histórico do shell e possivelmente em
# logs). O hash bcrypt é calculado localmente e só o hash vai pro cluster.
# Ver ../argocd/README.md pra fazer isso manualmente sem Terraform.
resource "null_resource" "argocd_admin_password" {
  count = var.argocd_admin_password != "" ? 1 : 0

  triggers = {
    # muda sempre que a senha desejada mudar, força reaplicar
    password_hash_input = var.argocd_admin_password
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail
      HASH=$(python3 -c "
      import bcrypt, sys
      print(bcrypt.hashpw(sys.stdin.readline().rstrip().encode(), bcrypt.gensalt(rounds=10)).decode())
      " <<< "$ARGOCD_PASSWORD")
      MTIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)
      KUBECONFIG=${var.kubeconfig_path} kubectl -n argocd patch secret argocd-secret -p \
        "{\"stringData\": {\"admin.password\": \"$HASH\", \"admin.passwordMtime\": \"$MTIME\"}}"
    EOT
    environment = {
      ARGOCD_PASSWORD = var.argocd_admin_password
    }
  }

  depends_on = [helm_release.argocd]
}
