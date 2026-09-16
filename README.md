# k3s-cilium-lab

Documentação e configuração completa da stack k3s que roda no
batata-server (`192.168.3.200`) — um Xeon de 2008, 4 núcleos, 3.3GiB de
RAM. Este documento existe pra que qualquer pessoa consiga reproduzir a
mesma stack do zero, em qualquer desktop ou servidor, entendendo não só
*o quê* foi configurado mas *por quê* — cada decisão aqui nasceu de uma
restrição real de hardware ou de um incidente real, não de preferência
estética.

Referência complementar: [página de acompanhamento do projeto](https://claude.ai/artifact/GCvjipTJcACJntfo2QXs9d)
(o "diário de bordo" vivo do projeto, com o mesmo conteúdo em formato de
página).

## Visão geral da arquitetura

A decisão estrutural mais importante deste projeto é: **nem tudo roda
dentro do k3s.** Duas categorias de workload coexistem no mesmo host:

```
┌─────────────────────────────────────────────────────────────┐
│ HOST · batata-server · 3.3 GiB RAM total                     │
│                                                                │
│  ┌───────────────────────────────────┐   ┌─────────────────┐ │
│  │ k3s (cgroup com teto de 1536Mi)    │   │ Processos nativos│ │
│  │                                     │   │ (systemd)        │ │
│  │  • Cilium (CNI + Gateway API)      │   │                  │ │
│  │  • ArgoCD (GitOps, hoje sem apps)  │   │  • MiniStack     │ │
│  │  • CoreDNS, metrics-server         │   │    (:4566)       │ │
│  │  • local-path-provisioner          │   │  • gitlab-runner │ │
│  │  • whoami (app de demonstração)    │   │    (executor     │ │
│  │                                     │   │     shell)       │ │
│  └───────────────────────────────────┘   └─────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

**Por que dividir assim?** Porque o k3s tem um teto de memória rígido
(1536Mi, imposto via cgroup no systemd) e qualquer coisa com uso de
recurso imprevisível — um emulador de AWS que pode ter picos de I/O, um
runner de CI cujo consumo depende do job que está rodando — compete
diretamente por esse teto junto com o control plane do próprio cluster.
Isso não é teórico: **essa mesma combinação (Kubernetes + carga
imprevisível) já derrubou a API do k3s de verdade, mais de uma vez** (veja
o log de incidentes). A resposta não foi "dar mais limite de recurso" —
foi tirar a carga imprevisível do k3s inteiramente.

## O que tem em cada pasta

| Pasta | Roda em | O que é | Por quê |
|---|---|---|---|
| `cilium/` | k3s | CNI + Gateway API + LoadBalancer (L2/LB-IPAM) | Tudo mais no cluster depende disso pra funcionar — é a primeira coisa a subir |
| `gateway-api/` | k3s | `Gateway` compartilhado + `HTTPRoute`s por aplicação | Substitui Ingress; expõe serviços via IP do próprio node, sem LoadBalancer externo |
| `argocd/` | k3s | Controlador GitOps | Instalado e saudável, mas hoje sem nenhuma Application customizada (uma tentativa de rollout de observabilidade foi revertida no mesmo dia — ver incidente 1) |
| `ministack/` | **host**, fora do k3s | Emulador de AWS local (S3/DynamoDB/SQS e 60+ serviços) | Terraform precisa de algo pra apontar; rodar fora do k3s evita que um `terraform apply` compita com o control plane |
| `gitlab-runner/` | **host**, fora do k3s | Executor nativo de CI/CD (executor `shell`) | Mesmo raciocínio do MiniStack: consumo de CI é imprevisível, não pertence dentro do teto de 1536Mi |

**Observabilidade (Loki, Prometheus/Grafana) foi deliberadamente removida
deste projeto** — uma tentativa de subir cinco charts Helm de uma vez só
causou thrashing de swap real e deixou a API do apiserver inacessível
(incidente 1, abaixo). A decisão foi mover observabilidade pra um segundo
servidor dedicado, em vez de tentar encaixá-la à força aqui.

## Cada componente, em detalhe

### Cilium (`cilium/`)

CNI que substitui completamente o `kube-proxy` (via `kubeProxyReplacement:
true`) e também assume o papel de Ingress Controller através da **Gateway
API** (não Ingress clássico — Gateway API é o sucessor oficial, com
modelo de permissões mais granular via `HTTPRoute`/`ReferenceGrant`).

Decisões de configuração que valem a pena entender:

- **Gateway API em modo host-network** (`gatewayAPI.hostNetwork.enabled:
  true`): o Envoy do Cilium liga a porta do Gateway diretamente no IP do
  node, em vez de criar um Service do tipo LoadBalancer com IP virtual
  próprio. Isso exigiu duas capabilities extras no container do Envoy
  (`NET_BIND_SERVICE` + `keepCapNetBindService: true`) pra conseguir
  abrir a porta 80/443 sem ser root.
- **L2 Announcements + LB-IPAM** (`l2announcements.enabled: true` +
  `loadbalancer-ippool.yaml`): como não existe um cloud provider real
  fornecendo IPs de LoadBalancer, o Cilium anuncia via ARP/NDP um pool de
  IPs (`192.168.3.201-210`) definido manualmente. `.202` por exemplo já
  foi usado pelo MiniStack quando ele ainda rodava dentro do cluster.
- **`resources:` em cada componente** (agent, operator, envoy): não são
  valores arbitrários — foram medidos observando o RSS real em regime
  permanente e documentados exatamente por causa dos incidentes de
  memória. Rodar `helm upgrade --dry-run` antes de qualquer mudança aqui
  é obrigatório: este chart controla o CNI, e um erro de configuração
  pode derrubar a rede do cluster inteiro.
- **ClusterMesh foi testado e desativado** — chegou a ser habilitado,
  nunca teve nenhum peer conectado (`0/0 remote clusters` o tempo todo), e
  consumia 3 containers sempre ativos (etcd, apiserver, kvstoremesh) por
  uma funcionalidade que não fazia nada. Em um host de 3.3GiB, isso é
  desperdício puro — foi desligado pra liberar memória de verdade, não só
  o teto.

### Gateway API (`gateway-api/`)

Um único `Gateway` (`my-gateway`) com um listener HTTP genérico (porta 80,
redireciona pra HTTPS) e um listener HTTPS **por aplicação**, cada um com
seu próprio hostname e certificado.

**A pegadinha mais importante deste projeto inteiro está aqui:** um
`HTTPRoute` (ou um listener do `Gateway`) sem `hostname` definido vira um
**catch-all para o Gateway inteiro** — ele passa a interceptar tráfego de
*qualquer* hostname, inclusive hostnames de aplicações adicionadas depois
dele. Isso já aconteceu de verdade: o `HTTPRoute` do `whoami` não tinha
hostname explícito e sequestrou silenciosamente as requisições destinadas
ao ArgoCD, servindo a página do whoami no lugar. A correção foi dar um
hostname explícito a toda rota, sem exceção — e essa regra está codificada
como comentário no próprio `httproute-whoami.yaml` pra nunca mais ser
esquecida.

### ArgoCD (`argocd/`)

Instalado com `server.insecure: true` porque o TLS é terminado no
Gateway, não no próprio `argocd-server` — a prática recomendada quando
existe um proxy/ingress na frente fazendo terminação de TLS.

`dex`, `notifications` e (na teoria) `applicationSet` estão desabilitados
pra reduzir footprint — sem SSO nem notificações em uso hoje. Vale notar
uma pegadinha do próprio chart: `applicationSet.enabled: false` **não**
impede o pod `applicationset-controller` de subir na versão 10.9.0 do
chart — ele sobe de qualquer forma, então em vez de lutar contra isso, o
componente ganhou um teto de recurso próprio pra pelo menos ser
contabilizado no orçamento de memória do host.

Ver `argocd/README.md` pra instruções de bootstrap de senha (via patch
direto do hash bcrypt no Secret, nunca em texto plano) e uma pegadinha
real do CLI `argocd` com esse Gateway específico (erro de ALPN/TLS ao
tentar `argocd login` via gRPC nativo — contornável com `--core` ou
`--grpc-web --skip-test-tls`).

### MiniStack (`ministack/`)

Emulador local de AWS ([ministackorg/ministack](https://github.com/ministackorg/ministack)),
escolhido especificamente por rodar S3/DynamoDB/SQS/IAM **em processo**,
sem precisar de socket do Docker — os serviços mais pesados com estado
real (RDS, ECS) precisariam de Docker e ficam fora de escopo aqui.

Roda como processo nativo via `pipx` (não existe Docker neste host, e
instalar um daemon de container só pra rodar um binário Python seria
overhead desnecessário num host já apertado). ~30MB de RAM em idle —
comparado aos ~64-256Mi que a mesma funcionalidade custava quando rodava
como Deployment dentro do k3s.

### GitLab Runner (`gitlab-runner/`)

Runner nativo, executor `shell` (não Docker, não Kubernetes), registrado
contra um projeto GitLab específico que hospeda o Terraform que usa o
MiniStack acima. Roda como serviço systemd executando diretamente como o
usuário `gitlab-runner`, sem privilégio de root e sem `su` por job (o
executor `shell` não precisa disso quando o daemon já roda como o usuário
certo).

**Este componente tem o incidente mais instrutivo do projeto** — ver
incidente 4 abaixo antes de reproduzir isso em outro host, porque o erro
que ele produz quando mal configurado é genérico ao ponto de ser
enganoso.

## Ordem de instalação

```
1. k3s em si                -- qualquer instalação recente serve; construído contra v1.36
2. cilium/                   -- CNI precisa existir antes de qualquer coisa conseguir agendar pods
3. gateway-api/               -- depende dos CRDs de Gateway API que o Cilium instala
4. argocd/                    -- precisa de um listener no Gateway + Secret de TLS pra sua rota
5. ministack/                -- independente, nível de host, a qualquer momento
6. gitlab-runner/             -- independente, nível de host; precisa de um projeto GitLab + token de runner
```

Os passos 2-4 também podem ser geridos via Terraform (`helm_release` +
`kubernetes_manifest` apontando pros mesmos arquivos de values aqui) no
projeto de origem, se preferir aplicar declarativamente em vez de rodar
cada chart manualmente — não incluído aqui pra manter este repositório
autônomo.

## Orçamento de capacidade

Total corrente de *requests* de memória do lado Kubernetes contra o teto
de 1536Mi do cgroup. Os limites somados passam disso — e isso é
proposital, não um erro: nem todo componente atinge o pico ao mesmo
tempo. A lição aprendida à força é que **requests, não limits, é o número
que importa de verdade** pra saber se algo cabe.

| Componente | Roda em | Request | Limit |
|---|---|---:|---:|
| cilium (agent + envoy + operator) | k3s | ~224Mi | ~512Mi |
| coredns, metrics-server, local-path-provisioner | k3s | ~88Mi | ~224Mi |
| argocd (5 componentes) | k3s | ~165Mi | ~688Mi |
| whoami (app de demonstração) | k3s | 8Mi | 32Mi |
| **total k3s** | | **~804Mi (52%)** | **~2890Mi (85%)** |
| MiniStack | host | ~30MB RSS | teto de 128M |
| gitlab-runner | host | ~20MB RSS | — |
| terraform CLI (transitório) | host | pico de ~300Mi, não residente | — |

Antes de adicionar qualquer componente novo a essa tabela, pergunte: ele
pode plausivelmente atingir seu pico de uso ao mesmo tempo que algo que
já está aqui? Foi exatamente essa pergunta não feita que causou o
incidente 1.

## Log de incidentes

Cada incidente aqui é a razão pela qual algo acima está configurado do
jeito que está — não é histórico decorativo, é a justificativa técnica
real por trás de cada decisão de design deste projeto.

### 1. Cinco Applications do ArgoCD sincronizadas ao mesmo tempo

Um rollout de observabilidade (VictoriaMetrics, kube-state-metrics,
node-exporter, Promtail, Grafana) foi aplicado de uma vez só. Cada
Application disparou um `helm pull` + template concorrente no
`repo-server` do ArgoCD. Resultado: iowait entre 67-94%, load average de
pico em 12.25, e a API do k3s começou a falhar handshakes TLS.

**Causa raiz:** a própria regra de "uma coisa por vez" já estava escrita
num rascunho anterior deste plano e não foi seguida na prática.

**Resolução:** todo o stack de observabilidade foi removido; observabilidade
foi definitivamente movida pra um segundo servidor.

### 2. Uma checagem de saúde piorou o incidente em andamento

Enquanto o incidente 1 acontecia, um `kubectl get pods -A -o wide` (pra
diagnosticar o problema) chegou bem no momento em que o datastore SQLite
do k3s (kine) já estava levando 2-3 segundos por escrita. Esse único
comando fez o swap saltar de 648Mi pra 1.4Gi.

**Lição:** a partir do momento em que o `kubectl` começa a dar timeout,
pare de usar `kubectl` inteiramente — inclusive comandos somente leitura.
Troque para `free -h`, `vmstat 1` e `k3s crictl` (nenhum dos três passa
pela API do apiserver).

### 3. Deletar uma Application do ArgoCD não deletou o que ela criou

Sem um finalizer de cascata configurado, deletar as `Application`s do
Grafana e do kube-state-metrics não removeu os `Deployment`s
correspondentes — o kubelet continuou reiniciando os pods em loop mesmo
depois da Application já não existir mais. Foi preciso deletar os
Deployments diretamente.

### 4. Todo job de CI falhava instantaneamente com um erro sem informação nenhuma

**O sintoma:** `ERROR: Job failed: prepare environment: exit status 1`,
com duração efetivamente zero, em **qualquer** job — inclusive um `echo
hi` totalmente vazio. Isso persistiu trocando o usuário, o shell, a
versão do GitLab Runner (testado em 19.3.3 e 17.11.0), instalando `git`,
configurando `builds_dir` explicitamente, e testando feature flags — nada
disso mudava o resultado. O GitLab Runner nunca expôs a causa real em
nenhum log, nem em nível debug.

**Causa raiz, encontrada via `strace -f` no processo do runner:** o
executor `shell` roda cada job através de `bash -l` (shell de **login**).
Todo shell de login executa `~/.bash_logout` ao sair, e o `.bash_logout`
padrão do Ubuntu chama `clear_console -q` pra limpar a tela "por
privacidade". Sem um terminal controlador — sempre o caso em CI —
`clear_console` sai com código 1, e esse código vira o exit code do shell
de login inteiro, que o GitLab Runner reporta como uma falha genérica de
"prepare environment" sem contexto nenhum. Nada relacionado ao pipeline
ou ao código Terraform jamais esteve errado.

**Correção:** uma linha no próprio `~/.bash_logout` do usuário Linux
`gitlab-runner` (não em `/etc/skel`, não em nenhum outro usuário):

```bash
[ -x /usr/bin/clear_console ] && /usr/bin/clear_console -q || true
```

Confirmado com um pipeline real de ponta a ponta depois: `terraform
apply` criando um bucket S3, uma tabela DynamoDB e uma fila SQS reais
contra o MiniStack.

**Lição para qualquer debugging futuro:** quando o erro de uma ferramenta
é genérico e os próprios logs dela não dizem mais nada nem em nível
debug, `strace -f -p <pid>` no processo pai é o caminho mais rápido até a
causa real — muito mais rápido do que adivinhar variável de configuração
por variável de configuração.

## Regras de sequenciamento

- **Sincronizar ou instalar uma coisa por vez em trabalho de
  GitOps/Kubernetes, sem exceção.** O incidente 1 aconteceu porque essa
  regra já existia num rascunho anterior deste plano e foi ignorada na
  prática.
- Nunca rode `terraform apply` (provider aws, contra o MiniStack) ao
  mesmo tempo que uma sincronização do ArgoCD ou um `helm upgrade` —
  ambos são documentados como capazes de gerar picos de memória
  independentes num hardware deste porte.
- No momento em que o `kubectl` começar a dar timeout, pare de usar
  `kubectl` — inclusive comandos somente leitura. Troque para `free -h`,
  `vmstat 1` e `k3s crictl` (todos contornam o apiserver) até confirmar
  que a API voltou a responder.
- Se `cilium` ou `cilium-envoy` for reiniciado por qualquer motivo,
  reinicie `cilium-operator` logo em seguida — o listener do Gateway API
  cai até isso ser feito, uma aspereza conhecida desta versão do chart em
  todo upgrade.
- Um `HTTPRoute` ou listener de `Gateway` sem hostname vira catch-all
  pra todo o resto — ver os comentários em `gateway-api/` pra a pegadinha
  real que isso já causou aqui.
- MiniStack e gitlab-runner não aparecem no `kubectl top` — são processos
  de host. Inclua os dois em qualquer revisão de `free -h`.
- Todo novo usuário de CI com executor shell precisa de um shell de login
  de verdade **e** de um `~/.bash_logout` inofensivo — ver
  `gitlab-runner/README.md`.
- Quando o erro de uma ferramenta é genérico e os logs dela não ajudam
  nem em modo debug, use `strace -f -p <pid>` no processo pai antes de
  ficar adivinhando variável de configuração por variável.
