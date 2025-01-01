# External Resources

Below are links to TMA resources that are not kept in this repository.
Because this project uses Azure and Terraform Enterprise, there are resources 
defined in other repositories that enable Azure and Terraform access for this project 
or are resources used by the TMA directly. To keep track of everything, links are included in this file.

## Azure Subscriptions

Package Security staging and production Azure subscriptions and associated role mappings are defined across several repositories. The actual subscriptions are created and managed by a security team. Below is table with links to the Azure 
subscription contributor entitlements and role mappings that the team has to create. These allow the team to access the Azure subscriptions.

| Environment  | Subscription Contributor Entitlement | Subscription Contributor Role Mapping |
| ------------ | ------------------------------------ | ------------------------------------- |
| Staging | [entitlements/ldap/apps/azure/azure-non-prod-supplychain-packagesecurity-contributor.txt](https://github.com/github/entitlements/blob/master/ldap/apps/azure/azure-non-prod-supplychain-packagesecurity-contributor.txt) | [azure-rbac/tf/rbac/subscription-non-prod-supplychain-packagesecurity.tf](https://github.com/github/azure-rbac/blob/main/tf/rbac/subscription-non-prod-supplychain-packagesecurity.tf) |
| Production | [entitlements/ldap/apps/azure/azure-prod-supplychain-packagesecurity-contributor.txt](https://github.com/github/entitlements/blob/master/ldap/apps/azure/azure-prod-supplychain-packagesecurity-contributor.txt) | [azure-rbac/tf/rbac/subscription-prod-supplychain-packagesecurity.tf](https://github.com/github/azure-rbac/blob/main/tf/rbac/subscription-prod-supplychain-packagesecurity.tf) |

## Terraform Enterprise (TFE) Organization

To give the team a private space for TFE workspaces, a Package Security TFE 
organization has been defined in the github/terraform-enterprise repository [here](https://github.com/github/terraform-enterprise/blob/master/config/organizations/package-security.yaml).

## Azure RBAC Roles

[Azure RBAC roles](https://learn.microsoft.com/en-us/azure/role-based-access-control/overview) are used to define access to Azure resources across Github. The 
definitions for these roles are defined in the [github/azure-rbac](https://github.com/github/azure-rbac) repository.

The project needs three RBAC roles for each environment:
- A role for team members to access the Azure portal
- A role for the service principal used by the TMA Moda service to authenticate with TMA Azure resources 
- A role for the service principal used to associate the TFE `trust-metadata-api` workspace with the Azure account and package-security subscription

### Package Security team RBAC Roles

- [Staging (aka non-prod) role](https://github.com/github/azure-rbac/blob/main/tf/rbac/subscription-non-prod-supplychain-packagesecurity.tf)
- [Production role](https://github.com/github/azure-rbac/blob/main/tf/rbac/subscription-prod-supplychain-packagesecurity.tf)

### Terraform Service Principal RBAC Roles

- [Staging (aka non-prod) TF service principal role](https://github.com/github/azure-rbac/blob/main/tf/rbac/spn-trust-metadata-api-non-prod_tf.tf)

The client IDs and secrets are automatically generated and stored in Vault after the principals are deployed. They are accessible like any other Vault secret. They 
are automatically rotated.

#### Terraform Enterprise Vault OIDC Access

- Staging
  - [OIDC role](https://github.com/github/vault-config/blob/master/config/cp1-iad-prd/auth/tfe/roles/package-security-default-trust-metadata-api-staging.json)
  - [Policy](https://github.com/github/vault-config/blob/master/config/cp1-iad-prd/sys/policy/token-terraform-trust-metadata-api-staging.json)

To avoid manually updating the rotated service principal secrets in the TFE 
workspaces, TFE uses an OIDC role to read secrets directly from Vault.

### Moda Service Principal RBAC Roles

- [Staging (aka non-prod) Moda service principal role](https://github.com/github/azure-rbac/blob/main/tf/rbac/spn-trust-metadata-api-non-prod.tf)

The client IDs and secrets are automatically generated and stored in Vault after the principals are deployed. They are accessible like any other Vault secret.

## Vault

[Project Vault definition](https://github.com/github/entitlements/blob/master/ldap/apps/vault-secrets/read-write/trust-metadata-api.txt)
