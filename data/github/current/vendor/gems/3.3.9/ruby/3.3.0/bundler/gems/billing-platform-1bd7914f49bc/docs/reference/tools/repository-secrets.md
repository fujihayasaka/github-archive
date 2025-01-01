# Repository Secrets

Overview of the different secrets used when building and deploying this application.

## Table of Contents

- [Details](#details)
  - [Actions workflow secrets](#actions-workflow-secrets)

## Details

### Actions workflow secrets

The credentials are maintained automatically by https://github.com/github/azure-rbac/blob/main/tf/rbac/spn-billing-platform.tf and stored in Vault in the following keys:

`spn_billing_platform` (secret)
`spn_billing_platform_client_id`
`spn_billing_platform_tenant_id`

When expired, the secret is rotated automatically but must be updated manually under the `AZURE_SPN_CLIENT_SECRET` key in both

- https://github.com/github/billing-platform/settings/secrets/actions
- https://github.com/github/billing-platform/settings/secrets/dependabot

We also keep a copy of these [credentials in 1Password](https://start.1password.com/open/i?a=LKXPAKKGYNBF7IOHIU6VPDFEU4&v=gb4quw7z4ozfp4ymwzxw6xiah4&i=wprxjsh4vzaclaks5n7appedda&h=github.1password.com) which also have to be kept in sync manually.
