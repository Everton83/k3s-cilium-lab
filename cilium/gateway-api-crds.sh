#!/usr/bin/env bash
# CRDs de Gateway API exigidos pelo Cilium 1.20 (canal standard, v1.6.1).
# O cluster originalmente vinha com a v1.1.0, que é antiga demais — o
# cilium-operator se recusava a iniciar o controlador do Gateway até esses
# CRDs serem aplicados.
#
# Rode ANTES (ou logo depois) de habilitar o gatewayAPI no release Helm do
# Cilium, depois reinicie o operator:
#   kubectl -n kube-system rollout restart deploy/cilium-operator
set -euo pipefail

GAPI_VERSION="v1.6.1"
BASE="https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/${GAPI_VERSION}/config/crd/standard"

for crd in gatewayclasses gateways httproutes referencegrants grpcroutes backendtlspolicies tlsroutes; do
  kubectl apply --server-side -f "${BASE}/gateway.networking.k8s.io_${crd}.yaml"
done
