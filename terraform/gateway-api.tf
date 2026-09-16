# Gateway compartilhado + HTTPRoutes. Usa kubernetes_manifest (recurso
# genérico) porque Gateway API é CRD, não um tipo nativo do provider
# kubernetes — lê os mesmos arquivos YAML mantidos em ../gateway-api/ pra
# referência manual / fallback via kubectl apply.

resource "kubernetes_manifest" "gateway_my_gateway" {
  manifest   = yamldecode(file("${path.module}/../gateway-api/gateway-my-gateway.yaml"))
  depends_on = [helm_release.cilium, null_resource.gateway_api_crds]
}

resource "kubernetes_manifest" "whoami_deployment" {
  manifest = yamldecode(
    [for d in split("\n---\n", file("${path.module}/../gateway-api/whoami-app.yaml")) : d if length(trimspace(d)) > 0][0]
  )
}

resource "kubernetes_manifest" "whoami_service" {
  manifest = yamldecode(
    [for d in split("\n---\n", file("${path.module}/../gateway-api/whoami-app.yaml")) : d if length(trimspace(d)) > 0][1]
  )
}

resource "kubernetes_manifest" "httproute_whoami" {
  manifest   = yamldecode(file("${path.module}/../gateway-api/httproute-whoami.yaml"))
  depends_on = [kubernetes_manifest.gateway_my_gateway, kubernetes_manifest.whoami_service]
}

# httproute-argocd.yaml guarda duas rotas no mesmo arquivo (a rota https +
# o redirect http->https) separadas por "---" — o parser HCL não faz split
# de múltiplos documentos YAML sozinho, então isso é feito manualmente aqui.
resource "kubernetes_manifest" "httproute_argocd" {
  manifest = yamldecode(
    [for d in split("\n---\n", file("${path.module}/../gateway-api/httproute-argocd.yaml")) : d if length(trimspace(d)) > 0][0]
  )
  depends_on = [kubernetes_manifest.gateway_my_gateway, helm_release.argocd]
}

resource "kubernetes_manifest" "httproute_argocd_https_redirect" {
  manifest = yamldecode(
    [for d in split("\n---\n", file("${path.module}/../gateway-api/httproute-argocd.yaml")) : d if length(trimspace(d)) > 0][1]
  )
  depends_on = [kubernetes_manifest.gateway_my_gateway, helm_release.argocd]
}
