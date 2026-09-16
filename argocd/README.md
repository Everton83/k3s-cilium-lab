# ArgoCD

Controlador GitOps do cluster. Até o momento, não gerencia nenhuma
Application customizada no batata-server (um rollout de observabilidade
foi tentado e revertido no mesmo dia — ver o log de incidentes em
`../README.md`) — está ativo e saudável, só que vazio.

## Instalação

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm install argocd argo/argo-cd \
  --version 10.9.0 -n argocd --create-namespace \
  -f values-batata.yaml
```

Requer `../gateway-api/gateway-my-gateway.yaml` e seu Secret `argocd-tls`
já aplicados antes (os CRDs de Gateway API vêm do chart do Cilium, ver
`../cilium/`) — `server.insecure: true` em `values-batata.yaml` assume
que o TLS termina naquele Gateway, não no próprio `argocd-server`.

## Configurando a senha de admin

Não faça `helm install --set` com senha em texto plano no histórico do
shell ou num arquivo versionado. Em vez disso, faça o patch do hash
bcrypt diretamente no Secret do próprio release:

```bash
NEWPASS='escolha-uma-senha'
HASH=$(python3 -c "
import bcrypt, sys
print(bcrypt.hashpw(sys.stdin.readline().rstrip().encode(), bcrypt.gensalt(rounds=10)).decode())
" <<< "$NEWPASS")
MTIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)
kubectl -n argocd patch secret argocd-secret -p \
  "{\"stringData\": {\"admin.password\": \"$HASH\", \"admin.passwordMtime\": \"$MTIME\"}}"
```

Verifique sem passar pelo CLI (útil se o próprio CLI `argocd` estiver com
problema — ver a pegadinha abaixo):

```bash
curl -sk --resolve argocd.192.168.3.200.nip.io:443:192.168.3.200 \
  -X POST https://argocd.192.168.3.200.nip.io/api/v1/session \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"admin\",\"password\":\"$NEWPASS\"}"
```
Um 200 com um `token` JWT no corpo confirma que o login que a interface
web faria de fato funciona.

## Pegadinha: o CLI `argocd` contra este Gateway

`argocd login argocd.192.168.3.200.nip.io` pode falhar com um erro de
TLS/ALPN através do Envoy Gateway do Cilium, independente de o login em
si ser válido (confirmado acima via curl). Duas alternativas que
funcionam em vez de brigar com o caminho gRPC nativo do CLI:

- `argocd login --core --kube-context <seu-contexto>` — fala direto com a
  API do Kubernetes via seu kubeconfig, pulando o Gateway inteiramente.
- Flags `--grpc-web --skip-test-tls` num `argocd login` normal, se
  precisar do CLI completo (não só do modo `--core`).
