#!/usr/bin/env bash
# Gateway API CRDs required by Cilium 1.20 (standard channel, v1.6.1).
# The cluster originally shipped v1.1.0 which is too old — the cilium-operator
# refused to start the Gateway controller until these were applied.
#
# Run BEFORE (or right after) enabling gatewayAPI in the Cilium Helm release,
# then restart the operator:  kubectl -n kube-system rollout restart deploy/cilium-operator
set -euo pipefail

GAPI_VERSION="v1.6.1"
BASE="https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/${GAPI_VERSION}/config/crd/standard"

for crd in gatewayclasses gateways httproutes referencegrants grpcroutes backendtlspolicies tlsroutes; do
  kubectl apply --server-side -f "${BASE}/gateway.networking.k8s.io_${crd}.yaml"
done
