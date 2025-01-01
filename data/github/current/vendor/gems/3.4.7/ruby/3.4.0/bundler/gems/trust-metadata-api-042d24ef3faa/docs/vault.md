# Vault

Sensitive environment variables, such as MySQL credentials, are stored securely in [Vault](https://thehub.github.com/security/security-operations/vault/).

A list of required environment variables can be referenced the `.envrc.example` file.

The Vault namespace for this service is `trust-metadata-api`.

## Working with Vault

(This assumes you have access to the [Vault Bastion Server](https://thehub.github.com/security/security-operations/vault/configuration-variables-for-applications/#viewing-and-setting-configuration-with-vault))

Connect to the bastion server:

```shell
ssh <github-handle>@vault-bastion.githubapp.com

. vault-login
```

### Viewing all secrets

`vault-secret --application trust-metadata-api`

### Viewing a specific secret

`vault-secret --application trust-metadata-api TMA_MYSQL_HOST`

### Adding a new secret

`vault-secret --application trust-metadata-api --key TMA_SOMETHING_TOKEN --prompt`

## Environments

The default GitHub Vault environment is `production` but you can define [non-production vault environments](https://thehub.github.com/security/security-operations/vault/configuration-variables-for-applications/#working-with-non-production-secrets).

To work with any other Vault environment other than `production`, use the `--environment` flag for all `vault-secret` commands.

```shell
# list secrets for the staging environment
vault-secret --application trust-metadata-api --environment staging

# viewing a specific secret for the staging environment
vault-secret --application trust-metadata-api --environment staging --key TMA_MYSQL_HOST
```

If you want to be sure you are working with `production` you can also specify with the `--environment` flag

```shell
# list secrets for the production environment
vault-secret --application trust-metadata-api --environment production
```
