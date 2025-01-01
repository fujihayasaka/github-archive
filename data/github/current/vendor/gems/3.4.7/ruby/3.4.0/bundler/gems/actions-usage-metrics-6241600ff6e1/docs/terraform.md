# Terraform

We use Terraform to deploy and manage our Azure resources. GitHub has a Terraform Enterprise (TFE) instance at <https://terraform.githubapp.com>.

Links:

- [actions-fusion Terraform Workspaces](https://terraform.githubapp.com/app/actions-fusion/workspaces)
- [actions-usage-metrics Terraform templates](/config/terraform/)
- [How to deploy your Terraform code using the Branch Deploy Workflow](https://github.com/github/CosmosDB/blob/main/docs/getting-started.md#how-to-deploy-your-terraform-code-using-the-branch-deploy-workflow)
- Service Principal: [`spn_actions_usage_metrics_tf`](https://portal.azure.com/?wa=wsignin1.0#view/Microsoft_AAD_IAM/ManagedAppMenuBlade/~/Overview/objectId/11195040-2f04-4612-b578-7a38de1b7288/appId/c165b091-d047-462a-9f92-25d7fa249ba6/preferredSingleSignOnMode~/null/servicePrincipalType/Application/fromNav/)
- TFE Team: [`actions-usage-metrics-ci`](https://terraform.githubapp.com/app/actions-fusion/settings/teams/team-yttGEF2uSoboho9n)
- Production: [GitHub - Prod - actions-usage-metrics-prod](https://portal.azure.com/?wa=wsignin1.0#@githubazure.onmicrosoft.com/asset/Microsoft_Azure_Billing/Subscription/subscriptions/3cae2114-1f62-430d-9a16-a29bff6024a5)
- Lab: [GitHub - NonProd - actions-usage-metrics-nonprod](https://portal.azure.com/?wa=wsignin1.0#@githubazure.onmicrosoft.com/asset/Microsoft_Azure_Billing/Subscription/subscriptions/6cce5ec9-a487-4144-be96-f1a8f55ace8f)

## Deploying

1. Create a pull request with terraform changes
1. Get the pull request approved (required by <https://github.com/github/branch-deploy>)
1. Wait for CI to succeed (required by <https://github.com/github/branch-deploy>)
1. Comment on the pull request with `.noop` to see the plan (does not require approval)
1. If the plan looks good, comment on the pull request with `.deploy` to apply the changes
1. Merge the pull request

## Updating the Terraform secret

See <https://ops.githubapp.com/docs/playbooks/actions/actions-usage-metrics/secret-rotations/rotate-terraform-token.md>
