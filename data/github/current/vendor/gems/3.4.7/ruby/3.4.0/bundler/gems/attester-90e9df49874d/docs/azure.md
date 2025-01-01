# Azure

## Subscriptions

Package Security staging and production Azure subscriptions and associated role
mappings are defined across several repositories. The actual subscriptions are
created and managed by a security team. Below is table with links to the Azure
subscription contributor entitlements and role mappings that the team has to
create. These allow the team to access the Azure subscriptions.

| Environment | Subscription Contributor Entitlement                                                                                                                                                                                     | Subscription Contributor Role Mapping                                                                                                                                                  |
| ----------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Staging     | [entitlements/ldap/apps/azure/azure-non-prod-supplychain-packagesecurity-contributor.txt](https://github.com/github/entitlements/blob/master/ldap/apps/azure/azure-non-prod-supplychain-packagesecurity-contributor.txt) | [azure-rbac/tf/rbac/subscription-non-prod-supplychain-packagesecurity.tf](https://github.com/github/azure-rbac/blob/main/tf/rbac/subscription-non-prod-supplychain-packagesecurity.tf) |
| Production  | [entitlements/ldap/apps/azure/azure-prod-supplychain-packagesecurity-contributor.txt](https://github.com/github/entitlements/blob/master/ldap/apps/azure/azure-prod-supplychain-packagesecurity-contributor.txt)         | [azure-rbac/tf/rbac/subscription-prod-supplychain-packagesecurity.tf](https://github.com/github/azure-rbac/blob/main/tf/rbac/subscription-prod-supplychain-packagesecurity.tf)         |

## Terraform Enterprise (TFE) Organization

To give the team a private space for TFE workspaces, a Package Security TFE
organization has been defined in the github/terraform-enterprise repository
[here](https://github.com/github/terraform-enterprise/blob/master/config/organizations/package-security.yaml).

## Azure RBAC Roles

[Azure RBAC roles](https://learn.microsoft.com/en-us/azure/role-based-access-control/overview)
are used to define access to Azure resources across Github. The definitions for
these roles are defined in the
[github/azure-rbac](https://github.com/github/azure-rbac) repository.

The project needs three RBAC roles for each environment:

- A role for team members to access the Azure portal
- A role for the service principal used by the Attester Moda service to
  authenticate with Attester Azure resources
- A role for the service principal used to associate the TFE `attester-*`
  workspaces with the Azure account and package-security subscription

### Package Security team RBAC Roles

- [Staging (aka non-prod) role](https://github.com/github/azure-rbac/blob/main/tf/rbac/subscription-non-prod-supplychain-packagesecurity.tf)
- [Production role](https://github.com/github/azure-rbac/blob/main/tf/rbac/subscription-prod-supplychain-packagesecurity.tf)

### Moda Service Principal RBAC Roles

- [Staging (aka non-prod) Moda service principal role](https://github.com/github/azure-rbac/blob/main/tf/rbac/spn-attester-non-prod.tf)
- [Production Moda service principal role](https://github.com/github/azure-rbac/blob/main/tf/rbac/spn-attester-prod.tf)

The client IDs and secrets are automatically generated and stored in Vault after
the principals are deployed. They are accessible like any other Vault secret.

### Terraform Service Principal RBAC Roles

- [Staging (aka non-prod) TF service principal role](https://github.com/github/azure-rbac/blob/main/tf/rbac/spn-attester-non-prod_tf.tf)
- [Production TF service principal role](https://github.com/github/azure-rbac/blob/main/tf/rbac/spn-attester-prod_tf.tf)

The client IDs and secrets are automatically generated and stored in Vault after
the principals are deployed. They are accessible like any other Vault secret.
They are automatically rotated.

## Azure Private Endpoint

To enable communication between the HSM within Azure and the Attester service in
Moda, a
[private endpoint](https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-overview)
is created to serve as the entrypoint to communicating with the HSM.

This private endpoint must be defined in the
[github/sites](https://github.com/github/sites) repository so the private
endpoint is created in the Azure virtual network and sub-network defined in this
repository.

All Attester private endpoint Terraform resources are prefixed with
`package-security-attester` and can be found alongside other services' private
endpoints in
[sites/azure-eastus/private_endpoints.tf](https://github.com/github/sites/blob/main/sites/azure-eastus/private_endpoints.tf).

If any changes need to be made to a private endpoint resource, merge your
approved [github/sites](https://github.com/github/sites) PR and ask a Compute
Foundation team member in
[#compute-foundation-support](https://github.slack.com/archives/CFQGRMUKH) to
run the private endpoints Terraform plan.

Once the endpoint has been updated, you will need to reaccept the incoming
connection request to the Key Vault in the
[networking tab](https://portal.azure.com/#@githubazure.onmicrosoft.com/resource/subscriptions/a0231bbd-fed8-4abc-bc8d-dc92d3e358bf/resourceGroups/Attester-Staging/providers/Microsoft.KeyVault/vaults/Attester-Staging/networking).

> [!IMPORTANT] 
> When using a private link to Azure it's important the service NOT
> configure a proxy. If a proxy is necessary to reach other external services,
> `*.vault.azure.net` should be added to the `NO_PROXY` config so that the
> private link connection can be properly routed.

## Github Data Center DNS configuration

To allow services from within the GitHub data centers (including Moda services)
to connect with the key vault using the regular key vault hostname
(\<key-vault-name\>.vault.azure.net), DNS forwarding must be added to the Puppet
repository in
[hieradata/provider/gpanel/dns-cache.yaml](https://github.com/github/puppet/blob/master/hieradata/provider/gpanel/dns-cache.yaml).
The Attester entries are prefixed with `attester` and can be found under the
`github::role::dns::cache::azure_private_link_zones` section. Both the regular
hostname and private link hostname must be included.
