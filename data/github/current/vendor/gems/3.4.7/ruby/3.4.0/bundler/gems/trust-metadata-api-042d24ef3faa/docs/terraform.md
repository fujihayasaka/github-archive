# Terraform

The Azure resource infrastructure is managed via Terraform Enterprise. All of the 
key vault resource definitions are kept in this repository. But some related resource 
definitions are kept in other teams' repositories, see [External Resources](./external-resources.md) for more.

It is recommended we use [tfenv](https://github.com/tfutils/tfenv) to manage Terraform versions for this project. A `.terraform-version` 
file is present in the `terraform/azure` directory.

## Accessing Terraform Enterprise

You can login to Terraform Enterprise one of the following ways:
1. Terraform Enterprise (Production) Okta tile
1. Running `terraform login terraform.githubapp.com` in the terminal (this will redirect you to the TFE UI)

## TFE Workspaces

- [Staging workspace](https://terraform.githubapp.com/app/package-security/workspaces/trust-metadata-api-staging)

## Terraform-Vault Connection

Terraform is able to read secrets from the `trust-metadata-api` Vault spaces 
using the [octovault](https://github.com/github/terraform-provider-octovault) 
Terraform provider. TFE uses this to access the service principal secrets that 
give it the ability to manage infrastructure in Azure. Without Vault access, 
the team would need to update the secret values in the TFE workspaces manually 
after they have been automatically rotated in Vault. The team is not 
responsible for rotating the secrets.

# Resources

- [Terraform Enterprise onboarding documentation](https://github.com/github/terraform-enterprise/blob/master/docs/onboarding.md)
