# Certificado self-signed pro listener HTTPS do ArgoCD no Gateway. Gerado
# via provider tls em vez de escrito à mão: a chave privada nunca é salva em
# disco fora do state, e o efeito é o mesmo de um `openssl req -x509`.

resource "tls_private_key" "argocd" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "argocd" {
  private_key_pem       = tls_private_key.argocd.private_key_pem
  validity_period_hours = 825 * 24
  early_renewal_hours   = 720
  allowed_uses          = ["key_encipherment", "digital_signature", "server_auth"]

  subject {
    common_name = "argocd.${var.node_ip}.nip.io"
  }
  dns_names    = ["argocd.${var.node_ip}.nip.io"]
  ip_addresses = [var.node_ip]
}

resource "kubernetes_secret" "argocd_tls" {
  metadata {
    name      = "argocd-tls"
    namespace = "default" # precisa estar no namespace do Gateway, não do argocd
  }
  type = "kubernetes.io/tls"
  data = {
    "tls.crt" = tls_self_signed_cert.argocd.cert_pem
    "tls.key" = tls_private_key.argocd.private_key_pem
  }
}
