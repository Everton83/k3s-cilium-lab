# terraform/

Receita pra subir toda a estrutura de `../` (Cilium, Gateway API, ArgoCD,
MiniStack, GitLab Runner) de forma declarativa, em vez de rodar cada
`install.sh`/`helm install` manualmente.

**Roda NO servidor alvo**, não numa máquina remota — é o único lugar com
acesso direto tanto à API do k3s (kubeconfig local) quanto ao host em si
(pra instalar MiniStack e GitLab Runner via `local-exec`).

## Pré-requisitos

- k3s já instalado e rodando (este projeto não gerencia a instalação do
  próprio k3s, só o que roda em cima dele — ver `../README.md`).
- `helm`, `kubectl`, `python3` com o módulo `bcrypt` disponíveis no PATH.
- Um token de runner do GitLab (`glrt-...`), se `install_gitlab_runner = true`.

## Uso

```bash
cd k3s/terraform
terraform init

TF_VAR_sudo_password='...' \
TF_VAR_gitlab_runner_token='glrt-...' \
TF_VAR_argocd_admin_password='...' \
  terraform apply
```

Nunca passe `sudo_password`, `gitlab_runner_token` ou
`argocd_admin_password` num arquivo `.tfvars` versionado — sempre via
variável de ambiente `TF_VAR_*` no momento do apply. Veja os comentários
de cada `variable` em `variables.tf` pro porquê.

## O que cada arquivo faz

| Arquivo | Recursos |
|---|---|
| `cilium.tf` | CRDs de Gateway API + release Helm do Cilium + LoadBalancer IPAM/L2 |
| `gateway-api.tf` | `Gateway` compartilhado + app `whoami` + `HTTPRoute`s |
| `tls-secrets.tf` | Certificado self-signed pro listener HTTPS do ArgoCD |
| `argocd.tf` | Release Helm do ArgoCD + bootstrap da senha de admin |
| `host-services.tf` | MiniStack e GitLab Runner — instalados no host, não no k3s |

## Coisas que este Terraform deliberadamente NÃO faz

- **Não reinicia o `cilium-operator` automaticamente** depois de um upgrade
  do Cilium, mesmo isso sendo necessário pra o listener do Gateway voltar a
  funcionar (ver a pegadinha em `../README.md`). Terraform não tem um jeito
  limpo de expressar "reinicie esse outro release depois que eu mudar
  aquele" — esse passo continua manual:
  ```bash
  kubectl rollout restart deployment cilium-operator -n kube-system
  ```
- **Não instala o próprio k3s.** Este projeto assume que o k3s já existe.
- **Não gerencia observabilidade** — deliberadamente ausente, ver o log de
  incidentes em `../README.md`.
