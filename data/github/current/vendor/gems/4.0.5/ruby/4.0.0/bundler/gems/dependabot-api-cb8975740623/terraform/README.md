This directory hosts the Terraform specification for Dependabot-api resources hosted in Azure.

The TL;DR summary is:
- We have a GitHub instance of [Terraform enterprise](https://terraform.githubapp.com).
- The files in this directory define the resources we want as well as connection details to a Terraform enterprise workspace.
- Terraform enterprise watches this repository on the default branch.
- There is a directory under `terraform/` for each environment.

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

If a pull request is opened that touches this directory then Terraform will run a plan automatically. When a pull request is merged, or any changes are pushed to the default branch, then there will be an option in Terraform enterprise to apply those changes. We have to login to the [terraform-enterprise](https://github.okta.com/home/githubincprod_terraformenterpriseproduction_1/0oa1ge90n1xzToGwd1d8/aln1ge95etun5ywpX1d8) and apply those changes.

### Subscription ID

The subscription IDs for Dependabot-api are:
- Prod: `subscription ID: 843be593-cd7a-457a-a7e6-f71f2e9ad014` `(subscription name: GitHub - Prod - Security Products - Dependabot-Updates)`

The subscription ID was created through this [PR](https://github.com/github/security-iam/issues/6889).

## How we authenticate to Azure

Dependabot-api's workspaces in Terraform Enterprise authenticate to Azure using [OIDC (Workload Identity Federation)](https://developer.hashicorp.com/terraform/cloud-docs/workspaces/dynamic-provider-credentials/azure-configuration). The `azurerm` provider is configured with `use_oidc = true`, and the following workspace variables are set in each TFE workspace:

- `TFC_AZURE_PROVIDER_AUTH` — enables OIDC authentication
- `TFC_AZURE_RUN_CLIENT_ID` — the client ID of the Azure AD App Registration with a federated identity credential
- `ARM_TENANT_ID` — the Azure tenant ID
- `ARM_SUBSCRIPTION_ID` — the Azure subscription ID

These variables are managed in a [Project variable set](https://terraform.githubapp.com/app/azure-security-dependabot-updates-prod/projects/prj-BaH3oqEdbwq6uzLf/settings/varsets) in Terraform Enterprise. Authentication is handled entirely via the OIDC federated identity credential issued by Terraform Enterprise at runtime.
