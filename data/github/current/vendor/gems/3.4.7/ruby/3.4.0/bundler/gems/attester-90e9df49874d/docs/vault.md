# Vault

Sensitive environment variables, such as MySQL credentials, are stored securely in [Vault](https://thehub.github.com/security/security-operations/vault/).

A list of required environment variables can be referenced the `.env.example` file.

The Vault namespace for this service is `attester`.

## Working with Vault

(This assumes you have access to the [Vault Bastion Server](https://thehub.github.com/security/security-operations/vault/configuration-variables-for-applications/#viewing-and-setting-configuration-with-vault))

Connect to the bastion server:

```shell
ssh <github-handle>@vault-bastion.githubapp.com

. vault-login
```

### Viewing all secrets

`vault-secret --application attester --environment staging`
`vault-secret --application attester --environment production`

## Environments

The default GitHub Vault environment is `production` but you can define [non-production vault environments](https://thehub.github.com/security/security-operations/vault/configuration-variables-for-applications/#working-with-non-production-secrets).

To work with any other Vault environment other than `production`, use the `--environment` flag for all `vault-secret` commands.

### Viewing a specific secret

`vault-secret --application attester --environment staging --key ATTESTER_RELEASE_HMAC_KEY`

### Adding a new secret

`vault-secret --application attester --environment production --key ATTESTER_RELEASE_HMAC_KEY --prompt`
