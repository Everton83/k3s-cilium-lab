#!/usr/bin/env bash
# Instalação/upgrade completo do Cilium, como aplicado atualmente no batata-server.
set -euo pipefail
cd "$(dirname "$0")"

helm repo add cilium https://helm.cilium.io/ 2>/dev/null || true
helm repo update cilium

# 1. CRDs de Gateway API (v1.6.1) — necessários antes do gatewayAPI funcionar
./gateway-api-crds.sh

# 2. Cilium
helm upgrade --install cilium cilium/cilium \
  --namespace kube-system --version 1.20.1 \
  -f values.yaml

# 3. LoadBalancer IPAM + L2 announcement
kubectl apply -f loadbalancer-ippool.yaml
kubectl apply -f l2-announcement-policy.yaml

# 4. Qualquer restart do agent/envoy derruba o listener do Envoy do Gateway até
#    o operator republicar o CiliumEnvoyConfig. Reinicie ele depois de todo upgrade.
kubectl -n kube-system rollout restart deploy/cilium-operator
kubectl -n kube-system rollout status  deploy/cilium-operator --timeout=120s
