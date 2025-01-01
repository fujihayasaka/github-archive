# Terraform specifications

This directory hosts the Terraform specification for turboscan resources hosted in Azure.

The TL;DR summary is:

- We have a GitHub instance of [Terraform enterprise](https://terraform.githubapp.com).
- The files in this directory define the resources we want as well as connection details to a Terraform enterprise workspace.
- Terraform enterprise watches this repository on the default branch.
- There is a directory under `terraform/` for each environment.
- Steps that cannot be automated should be [documented in our instructions for setting up a new stamp](https://github.com/github/proxima/blob/main/docs/poc/code-scanning.md).

## General docs

- [General Terraform docs](https://www.terraform.io/docs/)
- [GitHub Terraform onboarding docs](https://github.com/github/terraform-enterprise/blob/master/docs/onboarding.md#terraform-versions)
- [GitHub Terraform with Azure onboarding docs](https://github.com/github/terraform-enterprise/blob/master/docs/onboarding-azure.md)
- [hashicorp/azurerm docs](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)

## Using Terraform

### Logging in to Terraform

[Log in to terraform-enterprise using Okta](https://github.okta.com/home/githubincprod_terraformenterpriseproduction_1/0oa1ge90n1xzToGwd1d8/aln1ge95etun5ywpX1d8).

### Making changes

This is not intended to be a full intro to using Terraform. See the [Terraform docs](https://www.terraform.io/docs/) for more information.

If a pull request is opened that touches this directory then Terraform will run a plan automatically. When a pull request is merged, or any changes are pushed to the default branch, then there will be an option in Terraform enterprise to apply those changes.

## How we authenticate to Azure

The necessary values are stored in vault and as variables in terraform-enterprise under the [Vault Access variable set](https://terraform.githubapp.com/app/azure-dsp-code-scanning-experiences-prod/settings/varsets/varset-3Jie6TAiRW2SYSx2). These will be picked up when running any terraform operation using the `terraform.githubapp.com` remote and there should be no need to have the values locally.

The `VAULT_TOKEN` variable in terraform contains a key to the `codeql-query-console` vault. This allows us to read secrets from vault and avoid having to manually copy secrets into terraform variables.

### Subscription ID

The subscription IDs are hard-coded into the terraform files.

Our two subscription IDs are:

- Prod: `02688c9a-46f1-471a-99cf-545c30f7235d`
- Non-prod: `3a67b8ea-c2ed-49ee-b268-ed1999168b5f`

The prod subscription is used for multiple "prod" stamps including production and various Proxima stamps.

Also see the [full list of subscription IDs](https://github.com/github/azure/blob/main/docs/azure_subscriptions.md).

### Service principal (SPN)

The service principal credentials (`client_id`, `client_secret`, `tenant_id`) are stored in vault and are accessed in https://github.com/github/turboscan/blob/main/terraform/_modules/secrets/vault-secrets.tf. Strictly only the client secret is secret, but for convenience all the values are stored in one place in vault.

The service principal credentials are created and updated automatically by another terraform plan located at https://github.com/github/azure-rbac/blob/main/tf/rbac/spn-turboscan_tf.tf. Theoretically the credentials are updated automatically when they expire and there should be no changes needed to the `turboscan` terraform instance.

To view the values, log in to a production shell and run

```shell
. vault-login
vault-secret --application turboscan --environment terraform
```

You should be able to see values for the following keys:

- spn_github_code_scanning_tf
- spn_github_code_scanning_tf_client_id
- spn_github_code_scanning_tf_tenant_id
