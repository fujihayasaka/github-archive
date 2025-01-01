# Billing Platform

🚀💰

## Quick Start

New to the billing platform? Check out the [Docs](/docs/readme.md) to get an overview of the billing platform's general goals and concepts. Looking to integrate your product with the billing platform? Check out the [Integration Guide](/docs/how-to-guides/how-to-integrate-with-billing-platform.md).

### Billing Platform on Codespaces

Before getting started with your codespace, make sure to setup your own Cosmos resource. See [this doc](/docs/how-to-guides/how-to-setup-your-cosmos-resource-for-development.md) for instructions on how to set that up.

Upon creating a new Codespace, you will be prompted to log in to Azure. Do this using your `@githubazure` account (not your `@microsoft` account). If you are not presented with an `@githubazure` log in option, visit the [Azure Portal](https://portal.azure.com/#@githubazure.onmicrosoft.com/resource/subscriptions/57997474-7983-4d65-a2e3-83410c0e43b3/resourcegroups/billing-platform-dev/providers/Microsoft.DocumentDB/databaseAccounts/billing-platform-dev/dataExplorer) first to set it up.

Once you are logged into Azure, build the project and start the server to confirm things are working:

```bash
> script/build
> script/server
```

You can also check the [Azure billing-platform-dev data explorer](https://portal.azure.com/#@githubazure.onmicrosoft.com/resource/subscriptions/57997474-7983-4d65-a2e3-83410c0e43b3/resourcegroups/billing-platform-dev/providers/Microsoft.DocumentDB/databaseAccounts/billing-platform-dev/dataExplorer) and look for your database and collection. They should be named `[your-username]-[branch-name]`. Be sure to have JIT access to the `github-nonprod-pande-billing-testing-contributor` role before doing so (`.jit me to billing` will include it).

<details>
  <summary><b>Handling errors</b></summary>

  #### Missing `dev.env` file
  ```
  /workspaces/billing-platform/script/api: line 5: /workspaces/billing-platform/script/../dev.env: No such file or directory
  ```

  The solution is to run the following script

  ```shell
  set-remote
  ```

</details>

### Billing Platform inside Dotcom

Follow [this workflow](/docs/tutorials/run-billing-platform-in-dotcom-codespaces.md) to spin up a Codespace to develop
end-to-end features using Dotcom, Billing Platform, and a related service emitting
usage data (eg. Actions).

### I Messed ~~Something~~ Everything Up! What Do I Do?

To reset things and start over try the following:

```
> make clean
> build
> az logout // in case you logged into the wrong account for Azure
> set-remote // to reset your Azure login
> build
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
