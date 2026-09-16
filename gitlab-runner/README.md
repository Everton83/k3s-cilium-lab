# GitLab Runner

Executor de CI/CD nativo, em nível de host — não é um workload do k3s. O
consumo de recurso de um runner é imprevisível e cheio de picos (um
`terraform apply` sozinho gera picos de ~270-350Mi de RSS), exatamente o
tipo de carga que já desestabilizou este host antes quando empilhada com
outras coisas; ver o log de incidentes em `../README.md`.

## Instalação

```bash
./install.sh https://gitlab.com glrt-xxxxxxxxxxxxxxxxxxxx "meu-servidor (nativo, host, executor shell)"
```

O token é um **runner authentication token** (`glrt-...`) obtido na
página **Settings > CI/CD > Runners > New project runner** do projeto
alvo — não é o fluxo antigo de registration-token compartilhado, que
versões recentes do GitLab rejeitam.

## Pegadinha que este script já resolve

Todo job rodado pelo executor `shell` executa como um **shell de login**
(`bash -l`). Duas coisas sobre isso quebraram todo job aqui com o mesmo
erro sem informação nenhuma, independente do conteúdo do job:

1. **O usuário Linux do próprio runner precisa de um shell de verdade.**
   `/usr/sbin/nologin` (um padrão sensato pra maioria das contas de
   serviço) faz todo job falhar instantaneamente.
2. **`~/.bash_logout` roda quando esse shell de login termina.** O padrão
   do Ubuntu chama `clear_console -q` pra limpar a tela "por
   privacidade" — o que falha sem um terminal controlador (sempre o caso
   em CI), e *esse* código de saída vira o código de saída do job
   inteiro. O `install.sh` já corrige essa linha só pro usuário
   `gitlab-runner`, sem tocar em `/etc/skel` nem em nenhum outro shell.

Os dois problemas se manifestam de forma idêntica: `ERROR: Job failed:
prepare environment: exit status 1`, com duração efetivamente zero, e o
GitLab Runner nunca expõe a causa real em nenhum log, nem em nível
debug — inclusive num job totalmente mínimo tipo `echo hi`. Se isso
acontecer num host diferente deste, `strace -f -p <pid-do-gitlab-runner>`
enquanto dispara um job novo é o jeito mais rápido de confirmar se é o
mesmo problema ou um bug novo.

## Verificação

```bash
sudo systemctl status gitlab-runner
```
Depois faça um commit trivial num projeto onde esse runner está
registrado e acompanhe `sudo journalctl -u gitlab-runner -f` até aparecer
`Job succeeded`.
