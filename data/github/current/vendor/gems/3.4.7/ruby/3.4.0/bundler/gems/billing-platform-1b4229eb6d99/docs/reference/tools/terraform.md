# Terraform

Terraform usage in billing-platform is ever-evolving, as [CosmosDB paved path](https://github.com/github/cosmosdb) is also continually evolving. We officially adopted it as the canonical way we manage our infrastructure as part of [Proxima](./proxima/) onboarding, and should continue forward.\

> [!NOTE]
> This document outlines manual interaction with Terraform, but as the Cosmos paved path evolves, we may eventually be automatically making infrastructure changes as part of CI.

## Table of Contents

- [Details](#details)
  - [Requirements for developers](#requirements-for-developers)
  - [Instantiating your local Terraform environment](#instantiating-your-local-terraform-environment)
  - [Making infrastructure changes](#making-infrastructure-changes)
  - [How to deploy your Terraform code using the Branch Deploy Workflow](#how-to-deploy-your-terraform-code-using-the-branch-deploy-workflow)
- [References](#references)

## Details

### Requirements for developers

- Access to [Terraform Enterprise (TFE)](https://terraform.githubapp.com/app/organizations) authenticated through Okta
  - Relevant entitlement [here](https://github.com/github/entitlements/blob/b362a879bf6e55a7e91beaec9343dd7213d410ff/ldap/apps/terraform-enterprise/tfe-billing.txt)
- An API token created by TFE and stored as a codespace secret under `GH_CS_TERRAFORM_LOGIN_TOKEN`
  - Relevant page in Terraform can be found [here](https://terraform.githubapp.com/app/settings/tokens)
  - You can manage your codespaces secrets [here](https://github.com/settings/codespaces)

### Instantiating your local Terraform environment

> [!NOTE]
> If you started up the billing-platform dev environment in it's own Codespace, you should be automatically logged in to Terraform. If your dev environment is a copy of billing-platform inside of a dotcom codespace, you will need to run `.devcontainer/scripts/setup-terraform`

You can stand up your local environment by navigating in the console to the `config/terraform` directory, and running `terraform init`.
If you are going to make changes to a specific environment, then you'll want to move into the directory before moving on to the next `Making infracsture changes` step.

### Making infrastructure changes

With an environment set up, you're ready to make infrastructure changes. These are commands that you will find helpful when working with making infrastructure changes:

- `terraform plan` - shows a diff of the application state as stored on TFE and the state described in the code where you're running `terraform plan`. This is a safe no-op to infrastructure.
- `terraform apply` - shows a diff similar to `terraform plan`, and then gives a prompt asking for the user to type `yes` to confirm the changes. Once confirmed, changes are made through the app

When making infrastructure changes, the steps are generally:

1. Make changes in the code that you would like to see reflected in the infrastructure
2. Choose the environment you want to apply changes to by moving into the relevant env directory (/production, /prod-weu-01, etc.)
3. `terraform plan` - ensure that the changes listed in the diff are as you expect
4. `terraform apply` - once again, ensure the changes listed in the diff are as you expect, and if so, respond with `yes` to the prompt
5. Keep an eye on the apply action as it logs the actions it is taking, as it will report if something goes wrong or if it encounters an inconsistent state

> [!NOTE]
> The `plan` and `apply` commands above only interface with the directory you are in. If a change is made that would affect all infrastructure it is very important that you apply that change to all workspaces. This way, users who run `plan` and `apply` against these workspaces in the future won't encounter a diff that has more changes than they would expect.

### How to deploy your Terraform code using the Branch Deploy Workflow

Please note that this only works for changes that live in the `config/terraform` directory and not the sub environment directories.

We use the `terraform-branch-deploy` Action to deploy Terraform changes made in a PR.
It follows the [IssueOps deployment model](https://github.blog/2023-02-02-enabling-branch-deployments-through-issueops-with-github-actions/).

We use the `terraform-branch-deploy` Action to deploy Terraform changes made in a PR.
It follows the [IssueOps deployment model](https://github.blog/2023-02-02-enabling-branch-deployments-through-issueops-with-github-actions/).

1. Make changes in the code that you would like to see reflected in the infrastructure
1. Push your changes to a branch in your repo.
1. Open a PR for your branch.
1. Post a comment on your PR with the `.deploy noop` command to run a `terraform plan` and the branch deploy workflow will automatically post the results in the PR comments.
1. Review the Terraform plan result to ensure that your changes will be applied as expected.
1. It's recommended to get approval from your team to deploy your changes.
1. Post a comment on your PR with the `.deploy` command to run a `terraform apply` and the branch deploy workflow will automatically post the results in the PR comments.
1. Review the Terraform apply result to ensure that your changes were applied as expected.
1. Merge your PR.

## References

- Hashicorp provides a VSCode extension that provides IntelliSense, syntax validation, highlighting, formatting, etc. for working with Terraform files. You can find the extension [on the marketplace](https://marketplace.visualstudio.com/items?itemName=HashiCorp.terraform).
