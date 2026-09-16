# MiniStack

Local AWS emulator (github.com/ministackorg/ministack). Runs on the host,
not in k3s — see the Ledger's "What lives on the host" section for why.
S3, DynamoDB, SQS and 60+ other services run in-process without needing a
Docker socket; the heavier stateful ones (RDS, ECS) need Docker and aren't
in use here.

## Install

```bash
./install.sh
```

Edit `ministack.service` first if the target user isn't `batata` — `User=`
and `ExecStart=` both need to change together (pipx installs to
`$HOME/.local/bin`).

## Verify

```bash
curl http://<host-ip>:4566/_ministack/health
```
Returns a JSON map of service name → `"available"`.

## Using it

Point any Terraform `aws` provider block at it:

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
    s3       = "http://<host-ip>:4566"
    dynamodb = "http://<host-ip>:4566"
    sqs      = "http://<host-ip>:4566"
    # add any other service you're using -- see the health endpoint above
    # for the full list MiniStack emulates
  }
}
```
