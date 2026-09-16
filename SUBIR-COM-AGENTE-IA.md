# Roteiro para um agente de IA subir este ambiente

Este arquivo é uma instrução autocontida pra dar a um agente de IA (Claude
Code ou similar) com acesso de shell/SSH a um servidor Linux novo. Cole
este documento inteiro como o pedido inicial, ou peça ao agente pra ler
este arquivo primeiro. Ele foi escrito pra que o agente consiga executar
tudo sozinho, incluindo pausar pra pedir os segredos que só um humano pode
fornecer.

## Contexto que o agente precisa entender antes de agir

Este é o projeto **k3s-cilium-lab**: uma stack k3s + Cilium + Gateway API +
ArgoCD, com um emulador de AWS (MiniStack) e um runner de CI/CD
(GitLab Runner) rodando **fora** do cluster, no host. Foi construído e
documentado em cima de um servidor real com hardware fraco (Xeon de 2008,
4 núcleos, 3.3GiB de RAM) que **já sofreu incidentes reais de
swap-thrashing e apiserver travado** quando várias coisas foram instaladas
ao mesmo tempo. `README.md` (na raiz desta pasta) documenta esses
incidentes em detalhe — leia antes de instalar qualquer coisa.

**A regra mais importante deste projeto inteiro, e a que mais foi
quebrada na prática: instale/sincronize uma coisa por vez, e confirme que
está saudável antes de seguir pra próxima.** Se o hardware alvo for
parecido em porte (4 núcleos, poucos GB de RAM), essa regra não é
opcional. Se for um hardware bem mais robusto, ainda é uma prática segura,
só que menos crítica.

## O que verificar antes de começar

1. **Porte do hardware alvo.** Rode `nproc` e `free -h`. Se for parecido
   com o original (poucos núcleos, poucos GB), siga a ordem de instalação
   abaixo estritamente, um passo por vez, checando saúde entre cada um. Se
   for bem maior, ainda vale seguir a ordem, mas o risco de sobrecarga é
   menor.
2. **k3s já está instalado?** Este projeto não gerencia a instalação do
   k3s em si (só o que roda em cima dele). Se não estiver instalado, use
   o instalador oficial (`curl -sfL https://get.k3s.io | sh -`) com as
   flags equivalentes a `--disable=traefik --disable=servicelb
   --disable-kube-proxy --flannel-backend=none` (ver `../config.yaml`) —
   ou pergunte ao humano como ele quer que o k3s seja instalado, já que
   isso pode variar bastante por ambiente.
3. **Existe sudo sem senha para o usuário que vai rodar os scripts?** Se
   não, o agente vai precisar pedir a senha ao humano antes de rodar
   qualquer coisa em `../ministack/install.sh`,
   `../gitlab-runner/install.sh` ou `terraform/host-services.tf`.
4. **Existe um projeto GitLab com um runner token gerado?** Necessário só
   se for instalar o GitLab Runner. Se não existir, o agente deve
   perguntar a URL do GitLab e pedir pro humano gerar um token em
   Settings > CI/CD > Runners > "New project runner" — o agente não
   consegue gerar esse token sozinho.

## Segredos que só um humano pode fornecer

**Nunca adivinhe, nunca invente, e nunca peça pra rodar algo que exponha
um destes em texto plano num arquivo versionado.** Pare e pergunte:

- Senha de sudo do usuário Linux alvo (necessária pra `ministack/` e
  `gitlab-runner/`, e pro Terraform via `TF_VAR_sudo_password`).
- Token de runner do GitLab (`glrt-...`), se for instalar o GitLab Runner.
- Uma senha de admin pro ArgoCD, se quiser definir uma agora em vez de
  usar a autogerada do chart.

## Duas formas de executar

### Opção A — via Terraform (recomendada, ver `terraform/README.md`)

```bash
cd terraform
terraform init
TF_VAR_sudo_password='...' \
TF_VAR_gitlab_runner_token='glrt-...' \
  terraform apply
```

Isso aplica tudo numa única execução coordenada. **Mesmo assim**, depois
do apply, confirme cada componente individualmente (ver "Como verificar
cada passo" abaixo) antes de considerar o trabalho concluído — o
Terraform reportar sucesso não significa que o Cilium terminou de ficar
`Ready`, por exemplo.

### Opção B — manual, um componente por vez (mais lenta, mais segura em hardware fraco)

Siga esta ordem exata, **rodando o "Como verificar" de cada item antes de
seguir pro próximo**:

1. **Cilium**
   ```bash
   cd cilium && ./install.sh
   ```
   Verificar: `kubectl -n kube-system get pods` — `cilium-*`, `cilium-envoy-*`
   e `cilium-operator-*` todos `Running` e `1/1`/`Ready`.

2. **Gateway API**
   ```bash
   kubectl apply -f gateway-api/gateway-my-gateway.yaml
   kubectl apply -f gateway-api/whoami-app.yaml
   kubectl apply -f gateway-api/httproute-whoami.yaml
   ```
   Verificar: `kubectl get gateway my-gateway -o yaml` — condição
   `Programmed: True`. Depois `curl http://whoami.<ip-do-host>.nip.io/`
   retorna 200.

3. **ArgoCD** (precisa de um Secret de TLS antes — ver `terraform/tls-secrets.tf`
   pra gerar um via Terraform, ou gere um self-signed manualmente com `openssl`)
   ```bash
   helm repo add argo https://argoproj.github.io/argo-helm
   helm install argocd argo/argo-cd --version 10.9.0 -n argocd \
     --create-namespace -f argocd/values-batata.yaml
   kubectl apply -f gateway-api/httproute-argocd.yaml
   ```
   Verificar: `kubectl -n argocd get pods` todos `Running`. Depois, o
   bootstrap de senha em `argocd/README.md`.

4. **MiniStack** (independente do k3s, pode rodar a qualquer momento)
   ```bash
   cd ministack && ./install.sh
   ```
   Verificar: `curl http://<ip-do-host>:4566/_ministack/health` retorna
   JSON com os serviços `"available"`.

5. **GitLab Runner** (independente do k3s, precisa do token do GitLab)
   ```bash
   cd gitlab-runner && ./install.sh <url-do-gitlab> <token> "<descricao>"
   ```
   Verificar: `sudo systemctl status gitlab-runner` ativo. Depois, um
   commit de teste no projeto GitLab e acompanhar
   `sudo journalctl -u gitlab-runner -f` até `Job succeeded`.

## Erros conhecidos e como reconhecê-los

Estes já aconteceram de verdade neste projeto — se o agente ver algo
parecido, a causa provável já está documentada, não é um bug novo pra
investigar do zero:

- **`ERROR: Job failed: prepare environment: exit status 1` em todo job
  do GitLab Runner, mesmo um `echo` vazio.** Não é o pipeline. Ver
  `gitlab-runner/README.md` — quase certamente o usuário Linux do runner
  sem shell de login válido, ou o `~/.bash_logout` chamando
  `clear_console` sem TTY disponível. `gitlab-runner/install.sh` já
  corrige os dois; se o erro aparecer mesmo assim, `strace -f -p <pid>`
  no processo do runner enquanto dispara um job novo.
- **`kubectl` começando a dar timeout, load average subindo, iowait alto.**
  Pare de rodar comandos `kubectl` (inclusive leitura) e troque para
  `free -h` / `vmstat 1` / `k3s crictl` até a situação estabilizar. Não
  rode mais nada novo enquanto isso não normalizar — ver o log de
  incidentes em `README.md`.
- **Uma `Application` do ArgoCD foi deletada mas o Deployment continua
  rodando.** Delete o Deployment/DaemonSet diretamente — a Application
  não tinha finalizer de cascata.
- **Página errada aparecendo num hostname que deveria servir outra
  coisa.** Provavelmente um `HTTPRoute` ou listener de `Gateway` sem
  `hostname` explícito virou catch-all — ver a pegadinha documentada em
  `gateway-api/gateway-my-gateway.yaml`.

## Definição de "pronto"

O ambiente está corretamente no ar quando, nesta ordem:

1. `kubectl get nodes` mostra o node `Ready`.
2. `kubectl get pods -A` não mostra nada em `CrashLoopBackOff` ou
   reiniciando repetidamente.
3. `curl http://whoami.<ip-do-host>.nip.io/` responde 200.
4. `https://argocd.<ip-do-host>.nip.io` carrega a tela de login do ArgoCD.
5. (se instalado) `curl http://<ip-do-host>:4566/_ministack/health`
   responde com os serviços disponíveis.
6. (se instalado) `sudo systemctl status gitlab-runner` está `active
   (running)`, e um job de teste passou.

Se qualquer um desses falhar, **não tente "consertar" instalando mais
coisas em cima** — volte pro item que falhou, investigue com os comandos
de diagnóstico do próprio item (não `kubectl get pods -A -o wide` de
forma repetida — ver o incidente 2 em `README.md`), e só prossiga depois
de resolvido.
