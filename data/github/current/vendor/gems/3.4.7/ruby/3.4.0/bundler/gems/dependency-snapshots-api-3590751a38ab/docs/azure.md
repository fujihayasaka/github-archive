Dependency snapshots API has some resources deployed on azure, and this document is meant to summarize them.

At GitHub, the general approach for deployment of Azure resources at GitHub is to use [Terraform](./terraform.md). This documentation won't delve into terraform configuration too much, but will cover Azure specific topics.

#### IMPORTANT Azure Login Changes!
As of July 2023 (Q1FY24) your Azure Portal access is "scoped read only" unless you follow the _two-step process below, in order_:
1. Initialize an Okta JIT Session for Azure Portal access [here](https://jit-okta-bouncer.githubapp.com/azure) **BEFORE** logging into Azure Portal.
1. Remember to log into Azure Portal using your `<MSFT_handle>@githubazure.com` email address (not `@microsoft.com`!)


**Resource types we use:**

* Subscription
  * `An Azure subscription is a logical container used to provision related business or technical resources in Azure. It holds the details of all your resources like virtual machines (VMs), databases, and more. When you create an Azure resource like a VM, you identify the subscription it belongs to. It allows you to delegate access through role-based access-control mechanisms.`
  * A subscription is a top level container for azure resources, and it is normal to partition subscriptions by team, product, and environment.
    * View our [production subscription](https://portal.azure.com/#@githubazure.onmicrosoft.com/resource/subscriptions/e98e5af3-7319-4357-9296-0f572fc85b0b/overview) in Azure Portal
    * View the [resources](https://portal.azure.com/#@githubazure.onmicrosoft.com/resource/subscriptions/e98e5af3-7319-4357-9296-0f572fc85b0b/overview) associated with our prod subscription in Azure Portal
  * We have a production subscription for DS-API and a non-production subscription.
  * Access to our production subscription is controlled by terraform, and is granted to both our SPN (which can create new resources) and our team (which can read and have limited interaction with all resources)
* [Resource group](https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/manage-resource-groups-portal#what-is-a-resource-group)
  * `A resource group is a container that holds related resources for an Azure solution. The resource group can include all the resources for the solution, or only those resources that you want to manage as a group.`
  * We don't really use these much yet, so we have a single resource group for most things.
* [SPN](https://learn.microsoft.com/en-us/azure/active-directory/develop/app-objects-and-service-principals#service-principal-object)
  * Service principal name. We have [a single service principal](https://github.com/github/azure-rbac/blob/main/tf/rbac/SPN-DEPENDENCY_SNAPSHOTS_API.tf) for dependency snapshots. At GitHub, we say "SPN" everywhere but really this is a "Service Principal" object.
    * View our [production SPN](https://portal.azure.com/#view/Microsoft_AAD_RegisteredApps/ApplicationMenuBlade/~/Overview/appId/007188e4-9c97-429a-9283-9a2d412dcdb7/isMSAApp~/false) SPN in Azure Portal
    * A SPN is like a "user" for our service. The service uses the SPN to authenticate to azure resources. It is so much like a user that you can find the App Registration in the Azure Active Directory application.
  * The SPN has a key provided via vault, that is automatically rotated for our `production` vault environment (the default environment). The rotation is provided by an in house plugin called [`autocred`](https://github.com/github/autocred).
    * Other environments will not auto-rotate, so if there is an env using a different environment (like `lab-api`) it needs to be manually updated.
* [Storage](https://learn.microsoft.com/en-us/azure/storage/common/storage-introduction) Account
    * View our [production snapshot container](https://portal.azure.com/#@githubazure.onmicrosoft.com/resource/subscriptions/e98e5af3-7319-4357-9296-0f572fc85b0b/resourceGroups/ds-api-production/providers/Microsoft.Storage/storageAccounts/proddssnapshotsstorage/overview) in Azure Portal
    * View our [production snapshot blob storage account](https://portal.azure.com/#@githubazure.onmicrosoft.com/resource/subscriptions/e98e5af3-7319-4357-9296-0f572fc85b0b/resourceGroups/ds-api-production/providers/Microsoft.Storage/storageAccounts/proddssnapshotsstorage/overview) in Azure Portal
    * View our [development CosmosDB storage account](https://portal.azure.com/#@githubazure.onmicrosoft.com/resource/subscriptions/bf2356ad-9fb5-427d-8070-63c26283d1ae/resourceGroups/dsapi-development/providers/Microsoft.DocumentDb/databaseAccounts/dsapi-cosmosdb-dev/overview) in Azure Portal
  * A storage account is an abstraction in front of different storage APIs, including Queues, Tables, and Containers (which hold blobs).
  * We primarily use the containers storage API for DS-API today.
  * Our service authenticates to our storage account using our SPN.

FAQ

* Why am I seeing `AADSTS7000222: The provided client secret keys for app '007188e4-9c97-429a-9283-9a2d412dcdb7' are expired. Visit the Azure portal to create new keys for your app: https://aka.ms/NewClientSecret, or consider using certificate credentials for added security: https://aka.ms/certCreds.` ?
  * This should only happen if our SPN credentials have expired. Since we have automatic rotation enabled for production credentials, chances are that you're using a different vault environment and need to replicate the SPN key to that environment.
  * You can view the current secrets [here](https://portal.azure.com/#view/Microsoft_AAD_RegisteredApps/ApplicationMenuBlade/~/Credentials/appId/007188e4-9c97-429a-9283-9a2d412dcdb7/isMSAApp~/false) for the production `spn-dependency_snapshots_api` Service Principal here. Note that the `autocred` plugin ensures a new secret is generated, stored here, and rotated into the DS-API `production` Vault monthly.
  * Example: replace the `lab-api` SPN key that is expired with the up-to-date `production` key
      1. Log into an ops-shell host and perform a `. vault-login`
      2. Extract the production key: `PROD_SPN_KEY=$(vault-secret -a dependency-snapshots-api -e production -k spn_dependency_snapshots_api)`
      3. Replace the lab key: `vault-secret -a dependency-snapshots-api -e lab-api -k spn_dependency_snapshots_api -v "$PROD_SPN_KEY"`
      4. Re-deploy `dependency-snapshots-api/main` to `lab-api` environment and validate Azure access is restored

