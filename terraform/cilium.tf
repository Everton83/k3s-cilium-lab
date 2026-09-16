# CNI + Gateway API + LoadBalancer (L2/LB-IPAM). Ver ../cilium/values.yaml
# pro porquê de cada bloco de configuração — este arquivo só faz a wiring.

# Os CRDs de Gateway API não vêm com o chart do Cilium (o canal "standard"
# do próprio projeto Gateway API é quem publica). kubernetes_manifest não
# lida bem com aplicar o CRD e um recurso desse novo Kind na mesma run, então
# isso fica como um null_resource simples com kubectl, igual ao
# ../cilium/gateway-api-crds.sh original.
resource "null_resource" "gateway_api_crds" {
  provisioner "local-exec" {
    command = "KUBECONFIG=${var.kubeconfig_path} bash ${path.module}/../cilium/gateway-api-crds.sh"
  }
}

resource "helm_release" "cilium" {
  name       = "cilium"
  repository = "https://helm.cilium.io/"
  chart      = "cilium"
  version    = "1.20.1"
  namespace  = "kube-system"

  values = [file("${path.module}/../cilium/values.yaml")]

  depends_on = [null_resource.gateway_api_crds]

  # Upgrades de CNI recriam ds/cilium + ds/cilium-envoy, o que derruba o
  # listener externo do Envoy do Gateway API até o cilium-operator
  # republicar o CiliumEnvoyConfig. Terraform não consegue expressar
  # "reinicie este outro release depois que eu mudar", então esse passo
  # continua manual depois de qualquer apply que toque no Cilium:
  #   kubectl rollout restart deployment cilium-operator -n kube-system
}

resource "kubernetes_manifest" "loadbalancer_ippool" {
  manifest   = yamldecode(file("${path.module}/../cilium/loadbalancer-ippool.yaml"))
  depends_on = [helm_release.cilium]
}

resource "kubernetes_manifest" "l2_announcement_policy" {
  manifest   = yamldecode(file("${path.module}/../cilium/l2-announcement-policy.yaml"))
  depends_on = [helm_release.cilium]
}
