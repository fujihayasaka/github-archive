# How to set up your own Cosmos resource for Codespace development

We used to use a single resource for all Codespace development, but have experienced rate limiting with that approach. Hopefully, the following process serves as a better experience for everyone with respect to that problem! 🤞

## Table of Contents

- [Details](#details)
  - [Cosmos DB Emulator](#cosmos-db-emulator)
  - [View local Cosmos DB](#view-local-cosmos-db)
  - [Setup instructions](#setup-instructions)

## Details

### Cosmos DB Emulator

Use the `-e` or `--emulator` flags when running `script/server` to run the billing platform with the CosmosDB emulator. [Here is a document](https://learn.microsoft.com/en-us/azure/cosmos-db/emulator) to learn more about the emulator environment.

> [!NOTE]
> Running the server with the emulator will eventually be the default option when running `script/server`.

#### View local Cosmos DB

You can explore data for your local Cosmos DB by doing the following:

1. For github/github codespaces, you will need to forward port 8081 so that you can access the Cosmos DB explorer locally. This should be done by default in a github/billing-platform codespace. VS Code users can check the `PORTS` tab to verify that port `8081` is forwarded. If it isn't, click on the `Add Port` button and add `8081`. Non VS Code users can forward port `8081` using the following command: `gh cs ports forward 8081:8081`
2. Navigate to https://localhost:8081/_explorer/index.html and click the `Explorer` section to explore the data. If this page doesn't load, that is a sign that the Cosmos DB Emulator is not running.

### Setup instructions

Use these setup instructions only if you need a live Cosmos DB instance for development work.

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
