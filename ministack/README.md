# MiniStack

Emulador local de AWS (github.com/ministackorg/ministack). Roda no host,
não no k3s — ver a seção "Visão geral da arquitetura" em `../README.md`
pra entender o porquê. S3, DynamoDB, SQS e mais de 60 outros serviços
rodam em processo, sem precisar de socket do Docker; os mais pesados com
estado real (RDS, ECS) precisam de Docker e não estão em uso aqui.

## Instalação

```bash
./install.sh
```

Edite `ministack.service` antes se o usuário alvo não for `batata` —
`User=` e `ExecStart=` precisam mudar juntos (o `pipx` instala em
`$HOME/.local/bin`).

## Verificação

```bash
curl http://<ip-do-host>:4566/_ministack/health
```
Retorna um mapa JSON de nome do serviço → `"available"`.

## Como usar

Aponte qualquer bloco `provider "aws"` do Terraform pra ele:

```hcl
provider "aws" {
  region     = "us-east-1"
  access_key = "test"
  secret_key = "test"

  s3_use_path_style           = true
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    s3       = "http://<ip-do-host>:4566"
    dynamodb = "http://<ip-do-host>:4566"
    sqs      = "http://<ip-do-host>:4566"
    # adicione qualquer outro serviço que for usar -- ver o endpoint de
    # health acima pra lista completa do que o MiniStack emula
  }
}
```
