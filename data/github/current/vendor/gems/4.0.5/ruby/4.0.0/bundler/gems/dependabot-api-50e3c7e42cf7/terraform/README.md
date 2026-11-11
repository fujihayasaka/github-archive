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

### Service principal (SPN)

The service principal credentials, client secret (`spn_dependabot_api_tf`), client ID (`spn_dependabot_api_tf_client_id`), tenant ID (`spn_dependabot_api_tf_tenant_id`) are stored as variables in vault within the production environment of the Dependabot-api application. Strictly only the client secret is secret, but for convenience all the values are stored in one place.

To view the values, log in to a production shell and run the below commands [ref](https://github.com/github/dependabot-updates/issues/3934#issuecomment-1512192226):
```bash
. vault login
vault-secret --application dependabot-api --environment production

  "spn_dependabot_api_tf": "XXXYYYYZZZZZZZZZZZZZZZZZZZ",
  "spn_dependabot_api_tf_client_id": "7c03cxxxxyyyyyzzzzz",
  "spn_dependabot_api_tf_tenant_id": "398a6654-zzzyyyyzzzzzz"
```

The service principal was created through this [task](https://github.com/github/dependabot-updates/issues/3897). When creating a pull request for a service principal, it is necessary to specify the application name in the vault, which in our case is dependabot-api. Once the pull request for the service principal is merged, it generates all the necessary values (such as client ID, client secret, and tenant ID) and stores them in the application in the vault.

#### Updating service principal

The service principal credentials last for one year. By using octovault in Terraform to access the service principal by using vault token, we can leverage the benefit of having the service principal renew automatically every year by the vault team, thus eliminating the need for manual renewal. 

But for any reason, the service principal are out of date then changes in the terraform code in Dependabot-api repository will fail to apply and you will have to update the credentials. It is [not currently possible](https://github.com/github/security-iam/issues/4461#issuecomment-1016807635) to self-serve this process. Open an [new issue](https://github.com/github/security-iam/issues/new/choose) in the `security-iam` repository to request it.

## How we authenticate to Azure

To authenticate with Azure, Dependabot-api's [workspace](https://terraform.githubapp.com/app/azure-security-dependabot-updates-prod/workspaces/dependabot-api-staff-wus2-01) in terraform-enterprise requires access to service principal values stored in the vault. To achieve this, vault token is created that is also stored in the vault within the production environment of the Dependabot-api application. This token is added to the [variable set](https://terraform.githubapp.com/app/azure-security-dependabot-updates-prod/settings/varsets) in Terraform Enterprise. The `octovault provider` used in the Terraform code in the Dependabot-api repository will utilize this vault token to access all the service principal values (client ID, client secret & tenant ID) stored in the vault required to authenticate with Azure.

Since the vault token has been added to the variable set, it will be automatically detected during any Terraform operation using the terraform.githubapp.com remote, negating the need for the values to be stored locally.
