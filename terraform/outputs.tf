output "argocd_url" {
  value = "https://argocd.${var.node_ip}.nip.io"
}

output "whoami_url" {
  value = "http://whoami.${var.node_ip}.nip.io"
}

output "ministack_endpoint" {
  value = var.install_ministack ? "http://${var.node_ip}:4566" : null
}

output "ministack_health_check" {
  value = var.install_ministack ? "curl http://${var.node_ip}:4566/_ministack/health" : null
}
