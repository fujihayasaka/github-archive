# Managing Cloud Infrastructure with Terraform

Terraform is an open-source infrastucture as code software tool that provides a consistent CLI workflow to manage one or
multiple cloud services. Dependency Graph uses Terraform to manage our Azure Resources.

Terraform configuration can be found in `config/terraform` with a directory for each environment (e.g. `development`, `production`).

### First time developer setup:

1. Install terraform with `brew install terraform` (or run `script/bootstrap` to pickup DG's latest `Brewfile`).
1. Run `terraform login terraform.githubapp.com`, if you receive a `Forbidden` login with Okta first.

### For any environment that you haven't worked on before:

1. `cd config/terraform/development` or whatever environment you're going to edit.
1. Run `terraform init`

### General flow for changing infrastructure will look like:

1. Create a branch for your Terraform updates. Since `terraform plan` is only applied after the bits have been deployed to all environments,
you should only include your terraform changes in the pull request. Dependency Graph will break if code expects a cloud resource that does not exist.
1. Iterate locally with `terraform plan` from within a `config/terraform/<environment>` directory.
You can also run `terraform validate` to verify if configuration is valid.
1. Push changes (templates), create a PR, review and verify terraform checks are green.
![GitHub's Terraform PR Checks](assets/terraform_pr_checks.png)

1. Merge to master and go to [Terraform instance][tfe_github_app] to confirm changes and apply the plan.
<img alt="Terraform plan review" src="assets/terraform_plan_review.png" width="1000"/>

### Development Tools
Terraform has extensions for both VS Code and RubyMine, this improves productivity when updating the `.tf` files.
If Terraform CLI is failing locally, you can use the Terraform check on the pull request to help you debug what happened.

### Terraform Workspaces
Each Terraform workspace is linked to a specific environment within our `config/terraform` folder. You can view terraform organizations by
going to GitHub's [Terraform instance][tfe_github_app], you can access this app as well via Okta. Each workspace has the required
environment variables to establish connection to the right Azure Subscription. Terraform app is able to communicate to Azure on our behalf
because we created an Azure Service Principal identity for it, see [security-iam PR](https://github.com/github/security-iam/issues/3153).

### Azure Resources
For troubleshooting purposes, in order to access Azure Subscriptions directly you would need to do the following:

1. Go to https://portal.azure.com (I suggest to use browser in incognito mode if you have other Azure subscriptions)
1. When presented with AAD (Azure Active Directory), use `handle@githubazure.com`
1. (Optional) - You should be able to access our [NonProd](https://portal.azure.com/#@githubazure.onmicrosoft.com/resource/subscriptions/bf2356ad-9fb5-427d-8070-63c26283d1ae/overview) and [PROD](https://portal.azure.com/#@githubazure.onmicrosoft.com/resource/subscriptions/e8881bf9-9397-4235-b583-be4ab4a99711/overview) subscriptions


### Dependency Graph Terraform Onboarding
For more information about the onboarding, you can look at GitHub's [Terraform Enterprise documentation][tfe_docs] to get started.
[Entitlements][tfe_entitlements] and [Terraform organizations][tfe_dg_orgs] were already created for our [pizza team][dg_pizza_team], anyone should be able to access Azure Portal and view the aforementioned subscriptions.


## Resources and documentation:

- [GitHub's Enterprise Terraform Instance][tfe_github_app]
- [Official Terraform documentation](https://www.terraform.io/docs/index.html)
- [Azure Provider](https://www.terraform.io/docs/providers/azurerm/)
- [Azure Storage Account](https://www.terraform.io/docs/providers/azurerm/r/storage_account.html)
- [GitHub's Terraform onboarding documentation][tfe_docs]
- [GitHub's Terraform documentation repository](https://github.com/github/terraform-enterprise)
- Dependency Snapshots Terraform spec files:
  - [DS-API](https://github.com/github/dependency-snapshots-api/tree/main/config/terraform/production)
  - [Azure-RBAC](https://github.com/github/azure-rbac/blob/main/tf/rbac/SPN-DEPENDENCY_SNAPSHOTS_API.tf)

[tfe_docs]: https://github.com/github/terraform-enterprise/blob/master/docs/onboarding.md
[tfe_github_app]: https://terraform.githubapp.com/
[tfe_dg_orgs]: https://github.com/github/terraform-enterprise/pull/193
[tfe_entitlements]: https://github.com/github/entitlements/blob/master/ldap/apps/terraform-enterprise/tfe-dsp-dependency-graph.txt
[dg_pizza_team]: https://github.com/github/entitlements/blob/master/ldap/pizza_teams/dsp-dependency-graph.txt


Note: this was originally sourced from [this file](https://github.com/github/dependency-graph-api/blob/4a6a4557f21759adec206fd7c3ca0cf8425709e9/docs/terraform.md), but dg-api no longer needs to use terraform so we're moving it here.
