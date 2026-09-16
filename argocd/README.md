# ArgoCD

GitOps controller for the cluster. Not yet managing any custom Applications
on batata-server as of this writing (a same-day observability rollout was
tried and rolled back — see the Ledger's incident log) — it's live and
healthy, just empty.

## Install

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm install argocd argo/argo-cd \
  --version 10.9.0 -n argocd --create-namespace \
  -f values-batata.yaml
```

Requires `../gateway-api/gateway-my-gateway.yaml` and its `argocd-tls`
Secret applied first (Gateway API CRDs come from the Cilium chart, see
`../cilium/`) — `server.insecure: true` in `values-batata.yaml` assumes TLS
terminates at that Gateway, not at argocd-server itself.

## Set the admin password

Don't `helm install --set` a plaintext password into shell history or a
committed file. Patch the bcrypt hash directly into the release's own
secret instead:

```bash
NEWPASS='choose-one'
HASH=$(python3 -c "
import bcrypt, sys
print(bcrypt.hashpw(sys.stdin.readline().rstrip().encode(), bcrypt.gensalt(rounds=10)).decode())
" <<< "$NEWPASS")
MTIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)
kubectl -n argocd patch secret argocd-secret -p \
  "{\"stringData\": {\"admin.password\": \"$HASH\", \"admin.passwordMtime\": \"$MTIME\"}}"
```

Verify without going through the CLI (useful if the `argocd` CLI itself is
misbehaving — see the gotcha below):

```bash
curl -sk --resolve argocd.192.168.3.200.nip.io:443:192.168.3.200 \
  -X POST https://argocd.192.168.3.200.nip.io/api/v1/session \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"admin\",\"password\":\"$NEWPASS\"}"
```
A 200 with a JWT `token` in the body means the login the web UI would do
actually works.

## Gotcha: the `argocd` CLI vs this Gateway

`argocd login argocd.192.168.3.200.nip.io` can fail with a TLS/ALPN error
through Cilium's Envoy Gateway, independent of whether the login itself is
valid (confirmed above via curl). Two working alternatives instead of
fighting the CLI's native-gRPC path:

- `argocd login --core --kube-context <your-context>` — talks to the
  Kubernetes API directly via your kubeconfig, skips the Gateway entirely.
- `--grpc-web --skip-test-tls` flags on a normal `argocd login`, if you
  need the full CLI (not just `--core` mode).
