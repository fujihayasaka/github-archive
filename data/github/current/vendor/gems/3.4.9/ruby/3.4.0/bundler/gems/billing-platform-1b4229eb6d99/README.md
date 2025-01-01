# Billing Platform

🚀💰

## Quick Start

New to the billing platform? Check out the [Docs](/docs/readme.md) to get an overview of the billing platform's general goals and concepts. Looking to integrate your product with the billing platform? Check out the [Integration Guide](/docs/how-to-guides/how-to-integrate-with-billing-platform.md).

## Billing Platform on Codespaces

### Using Billing Platform with Cosmos DB Emulator

By default, running the following commands will run the Billing Platform using a Cosmos DB Emulator. If you need to use a real Azure Cosmos DB instance for development purposes, read [this](docs/how-to-guides/how-to-setup-your-cosmos-resource-for-development.md#azure-cosmos-db).

To start the server run:

```bash
script/server
```

To start the server in debug mode run:

```bash
script/server -d
```

### Billing Platform inside Dotcom

Follow [this workflow](/docs/tutorials/run-billing-platform-in-dotcom-codespaces.md) to spin up a Codespace to develop
end-to-end features using Dotcom, Billing Platform, and a related service emitting
usage data (eg. Actions).

### I Messed ~~Something~~ Everything Up! What Do I Do?

If you are just attempting to run the server itself, try:

```
make clean
script/server
```

If you are using another script and seeing messages like:

```
/workspaces/billing-platform/script/api: line 5: /workspaces/billing-platform/script/../dev.env: No such file or directory
```
Reset the environment variables with:

```shell
set-remote-emulator
```

## Additional Docs

- [Testing](/docs/reference/project/testing.md)
- [Debugging](/docs/reference/project/debugging.md)
- [ID and Partition Key Reference](/docs/reference/project/id-partitionkey-reference.md)
- [Folder Structure](/docs/reference/project/folder-structure.md)
- [Reference Documentation](/docs/reference/readme.md)
- [Transitions](/docs/reference/project/transitions.md)
- [Monitoring](/docs/reference/project/monitoring.md)

## Resources

- [Admin tool (production)](https://billing-platform-admin-prod-dotcom.githubapp.com/) - Okta auth required as well as [the `billing-platform-admin` entitlement](https://github.com/github/entitlements/blob/master/ldap/apps/okta-network-gateway/billing-platform-admin.txt).
- [Moda Application](https://devportal.githubapp.com/devportal/apps/billing-platform)
- [Hydro Usage Schema](https://hydro.githubapp.com/schemas/billingplatform-v1-Usage)
- [CosmosDB (Dev)](https://portal.azure.com/#@githubazure.onmicrosoft.com/resource/subscriptions/57997474-7983-4d65-a2e3-83410c0e43b3/resourceGroups/billing-platform-dev/providers/Microsoft.DocumentDb/databaseAccounts/billing-platform-dev/overview)
- [CosmosDB (Prod)](https://portal.azure.com/#@githubazure.onmicrosoft.com/resource/subscriptions/04b4bc34-e931-4274-82d6-f5b61c8fc48e/resourceGroups/data/providers/Microsoft.DocumentDb/databaseAccounts/billing-platform/overview) - If you need to access our production Cosmos database, you will need to have JIT access to the `github-prod-pande-billingplatform-contributor` role. You will also need to add your IP to the firewall rules. You can do this by adding your IP to the `additional_ips_to_allow` list in our `config/terraform/main.tf` file. See this
[doc](/docs/reference/tools/terraform.md) for more information about how to make this change. Please do not add your IP manually in the Azure Portal as this will get picked up as a change when `terraform plan/apply`-ing new changes. This can block those who are trying to  apply changes and your IP will potentially get kicked off anyways.
- [CosmosDB (CI)](https://portal.azure.com/#@githubazure.onmicrosoft.com/resource/subscriptions/57997474-7983-4d65-a2e3-83410c0e43b3/resourceGroups/billing-platform-dev/providers/Microsoft.DocumentDb/databaseAccounts/billing-platform-ci/overview)
- [Azure PAv2 (Dev)](https://ms.portal.azure.com/#@microsoft.onmicrosoft.com/resource/subscriptions/406caf86-7ab7-4e28-b59f-94d7f99980fa/resourceGroups/billing-nonprod573dad/providers/Microsoft.Storage/storageAccounts/billingnonprod573dad/overview)


## Support

Billing Platform is maintained by [@github/gitcoin](https://github.com/github/gitcoin). Refer to the [Service Catalog](https://catalog.githubapp.com/services/billing-platform/support) for the most up-to-date information on getting support.
