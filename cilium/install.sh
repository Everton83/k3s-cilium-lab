#!/usr/bin/env bash
# Full Cilium install/upgrade as currently applied on batata-server.
set -euo pipefail
cd "$(dirname "$0")"

helm repo add cilium https://helm.cilium.io/ 2>/dev/null || true
helm repo update cilium

# 1. Gateway API CRDs (v1.6.1) — required before gatewayAPI works
./gateway-api-crds.sh

# 2. Cilium
helm upgrade --install cilium cilium/cilium \
  --namespace kube-system --version 1.20.1 \
  -f values.yaml

# 3. LoadBalancer IPAM + L2 announcement
kubectl apply -f loadbalancer-ippool.yaml
kubectl apply -f l2-announcement-policy.yaml

# 4. Any agent/envoy restart drops the Gateway Envoy listener until the operator
#    re-pushes the CiliumEnvoyConfig. Bounce it after every upgrade.
kubectl -n kube-system rollout restart deploy/cilium-operator
kubectl -n kube-system rollout status  deploy/cilium-operator --timeout=120s
