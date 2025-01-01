# How to set up your Cosmos DB for development

This document outlines the various ways we work with Cosmos DB when developing billing-platform inside codespaces. The default, and recommened, approach is to use the Cosmos DB Emulator.

## Table of Contents

- [Cosmos DB Emulator (Recommended)](#cosmos-db-emulator-recommended)
  - [View Local Cosmos DB](#view-local-cosmos-db)
- [Azure Cosmos DB](#azure-cosmos-db)
  - [View Azure Cosmos DB](#view-azure-cosmos-db)
- [Standalone Cosmos DB Account (Legacy, Not Recommended)](#standalone-cosmos-db-account-legacy-not-recommended)

## Cosmos DB Emulator (Recommended)

By default, using `script/server` to run the billing platform will run it with the Cosmos DB Emulator. [Here is a document](https://learn.microsoft.com/en-us/azure/cosmos-db/emulator) to learn more about the emulator environment.

### View Local Cosmos DB

You can explore the data in your local Cosmos DB by doing the following:

1. For github/github codespaces, you will need to forward port 8950 so that you can access the Cosmos DB explorer locally. This should be done by default in a github/billing-platform codespace. VS Code users can check the `PORTS` tab to verify that port `8950` is forwarded. If it isn't, click on the `Add Port` button and add `8950`. Non VS Code users can forward port `8950` using the following command: `gh cs ports forward 8950:8950`
2. Navigate to https://localhost:8950/_explorer/index.html and click the `Explorer` section to explore the data. If this page doesn't load, that is a sign that the Cosmos DB Emulator is not running.

## Azure Cosmos DB

If for any reason you need to test against an actual Azure Cosmos DB instance, you can do so with `script/server -c`. This will create a Cosmos DB in the shared [billing-platform-dev](https://portal.azure.com/#@githubazure.onmicrosoft.com/resource/subscriptions/57997474-7983-4d65-a2e3-83410c0e43b3/resourceGroups/billing-platform-dev/providers/Microsoft.DocumentDb/databaseAccounts/billing-platform-dev/dataExplorer) Cosmos account in the `GitHub - NonProd - PandE - Billing/testing` subscription and connect to it.

> [!NOTE]
> This will create a Cosmos DB in the form of `<user>-<branch-name>` inside the `billing-platform-dev` Cosmos account that will persist even after you stop/delete your codespace.
> Please remember to run `script/clean -delete-databases` to delete any databases in the `billing-platform-dev` account associated with your username.
>
> This can be done from any codespace, but keep in mind it will delete _all_ of your current databases if you are using this method across multiple codespaces/branches.

### View Azure Cosmos DB

You can explore the data in your remote Cosmos DB by doing the following:

1. Send the chatop `.jit me to billing in roles for 10h because billing work` to @Hubot in the `#billing-ops` Slack channel to obtain proper authorization for viewing and querying resources in Azure Portal.
2. Navigate to the shared Cosmos DB account [billing-platform-dev](https://portal.azure.com/#@githubazure.onmicrosoft.com/resource/subscriptions/57997474-7983-4d65-a2e3-83410c0e43b3/resourceGroups/billing-platform-dev/providers/Microsoft.DocumentDb/databaseAccounts/billing-platform-dev/dataExplorer).
3. Note which branch you were on when starting the server, and search the list of DBs for one that matches `<your-username>-<branch>` and select it.
4. Expand the container in that DB and select `Items` to view the contents of your DB.

## Standalone Cosmos DB Account (Legacy, Not Recommended)

Prior to having the Cosmos DB Emulator available, we sometimes ran into rate limiting issues when using the shared `billing-platform-dev` Cosmos DB account. To get around that, developers could spin up their own Cosmos Accounts with the steps below, though this is no longer recommended. That being said, this guide will remain here as it might be helpful in some niche situations.

> [!WARNING]
> Only use this method if you absolutely need to. Spinning up additional Cosmos DB accounts in Azure means more resources to manage for security risks and compliance. If you do use these instructions, please delete your Cosmos DB account ASAP when you are done.

1. Send the chatop `.jit me to billing in roles for 10h because billing work` to @Hubot in the `#billing-ops` Slack channel to obtain proper authorization for creating resources in Azure Portal.
2. Go to the [Azure Portal](https://portal.azure.com/#home), logging in with your `<username>@githubazure.com` account.
3. Click `Azure Cosmos DB` at the top (or `+ More Services` if you don't see it).
4. On the next page, click `+ Create`.
5. Choose the `Azure Cosmos DB for NoSQL` API resource type.
6. Next, create the resource with the following settings based on the `billing-platform-dev` resource. Most notably:
   - Choose the Subscription named `GitHub - NonProd - PandE - Billing/testing`.
   - Choose the Resource Group named `billing-platform-dev`.
   - Use a different `Account Name`, such as `<username>-billing-platform-dev`.
   - Pick a `Location` value that aligns with your personal [Codespaces region setting](https://github.com/settings/codespaces).
   - The rest of the settings should be satisfied by the default values.
   - Complete settings summary:
     ![Cosmos resource config](/docs/images/cosmos_resource_config.png)
7. After clicking `Review and create` and getting a successful validation status, don't forget to click the `Create` button (again) to actually generate your resource!
   - :warning: If you receive a validation failure here that includes `AuthorizationFailed` errors, they will likely be resolved if you logout of the Azure Portal and log back in again.
8. Finally, when your resource is finished deploying, click `Go to resource`, then go to `Keys`. From there, copy the `PRIMARY CONNECTION STRING` value.
9. Go into your personal GitHub account's [Codespaces settings](https://github.com/settings/codespaces), create a new secret named `DEV_COSMOS_KEY`, and paste the copied connection string into its value. Make sure that you grant repository access to both the `github/github` and `github/billing-platform` repos.
10. Create a new codespace.
11. Run `script/server -c` to run the billing platform with an Azure Cosmos DB resource
