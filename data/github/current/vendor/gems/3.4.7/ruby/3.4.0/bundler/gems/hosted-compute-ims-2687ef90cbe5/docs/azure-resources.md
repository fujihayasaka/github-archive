# Azure Resources

IMS service uses Azure subscriptions under `githubazure` tenant to create and manage the following resources:
- [storage accounts](https://learn.microsoft.com/en-us/azure/storage/common/storage-account-overview) - to store VHD blobs temporary during image provisioning.
- [compute galleries](https://learn.microsoft.com/en-us/azure/virtual-machines/azure-compute-gallery) - to store curated and customer images, manage replications and sharing images to Resource Provider and Larger Runners services.

Every IMS environment has its own set of Azure subscriptions which are stored in the [azure_subscription](https://github.com/github/hosted-compute-ims/blob/main/schema/azure_subscription.sql) database table:
- Every Azure Subscription has own limit of image versions which can be assigned to subscription. When all existing azure subscription are near the limit, we need to provision new azure subscriptions manually and add them to IMS database. Check [How to provision new Azure Subscription](#how-to-provision-new-azure-subscriptions) to learn how to do it.  
- Every Azure Subscription has own `resources_prefix`. It is unique value which is appended to all resources created on the subscription. It ensures that all resource naming is unique across the whole Azure.

Learn more about Azure Resources Layout in [Improve Azure Resources Layout ADR](./adrs/2025-01-improve-azure-resources-layout.md).

### Azure subscriptions

The following naming convention is used for azure subscriptions:
- Dev environment: `GitHub - NonProd - Dev - Hosted Compute IMS - 001`, `GitHub - NonProd - Dev E2E - Hosted Compute IMS - 001`
- Lab environment: `GitHub - NonProd - Lab - Hosted Compute IMS - 001`
- Production environment: `GitHub - Prod - Hosted Compute IMS - 001`
- Proxima environments: `GitHub - Prod - Hosted Compute IMS for staff-wus2-01 - 001`, `GitHub - Prod - Hosted Compute IMS for prod-weu-01 - 001`

### Azure subscription access

The following entitlements are used for granting access to azure subscriptions:
- Dev environment: [azure-hosted-compute-ims-dev-contributor](https://github.com/github/entitlements/blob/master/ldap/apps/azure/azure-hosted-compute-ims-dev-contributor.txt)
- Lab environment: [azure-hosted-compute-ims-lab-contributor](https://github.com/github/entitlements/blob/master/ldap/apps/azure/azure-hosted-compute-ims-lab-contributor.txt)
- Prod and Proxima environments: [azure-hosted-compute-ims-prod-contributor](https://github.com/github/entitlements/blob/master/ldap/apps/azure/azure-hosted-compute-ims-prod-contributor.txt)

By default, users listed in entitlements have `Reader` access on subscriptions. If you need a `Contributor` role, you should perform a JIT request using one of the following ways:
- https://jit-okta-bouncer.githubapp.com/azure
- Hubot command: `.jit me to azure-hosted-compute-ims-lab-contributor in azure for <duration> because <reason>`

### How to provision new Azure Subscriptions

1. Create azure subscription
    - Follow the guide to request a new Azure Subscription: https://github.com/github/security-iam/blob/master/docs/how_to_azure_subscription.md
    - It is not required to generate a separate entitlement and jit config for every new subscription. We should be able to reuse existing prod entitlement and prod git config for all new production subscriptions
2. Make sure that IMS SPN (Service Principal) has the following roles on subscription: `Contributor`, `Storage Blob Data Contributor`
3. Request a bump of image definition limits for subscription
    - By default, Azure has the following limits: `1000 image definitions per subscription per region`, `10000 image versions per subscription per region`. With our [azure resources layout](./adrs/2025-01-improve-azure-resources-layout.md), these limits allow us to use only 1000 image versions slots per subscription because the worst case is 10k image definitions x 1 image version.
    - Azure Gallery team makes an exception for us and bump image definitions limit 10k. With this exception applied, we can effectively store 10000 image versions on every subscription.
    - To apply exception for new subscription, write an email to `Sandeep.Raichura@microsoft.com`, explain that we are GitHub Actions team and share the list of azure subscriptions where exceptions should be applied.
    - You will also need to specify region for exception. Choose the region which is defined in `AZURE_IMAGE_LOCATION` variable for environment where you add azure subscription.
    - Note: To check this Register the `Compute` resource provider (Go to `https://portal.azure.com/#@githubazure.onmicrosoft.com/resource/subscriptions/SUB_ID_HERE/resourceproviders` then go to the Quota tab for the subscription and search for `Gallery Images` (Go to `https://portal.azure.com/#@githubazure.onmicrosoft.com/resource/subscriptions/SUB_ID_HERE/quotas`). `Gallery Image` should be set to `10,000` the default it `1000`.
4. Generate a new resource prefix for subscription and ensure it is unique
    - Resource Prefix is used to ensure unique resource names because some Azure Resource names must be unique across the whole Azure. For example, storage account name.
    - You can use the following pwsh command to generate unique resource prefix for subscription: `[System.BitConverter]::ToUInt32([System.Security.Cryptography.MD5]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes($subscriptionId)))`
    - Use `az storage account check-name --name "ims<resourcePrefix>"` (ex: `az storage account check-name --name "ims1485582203"`) to confirm that resource naming is unique and it won't cause naming collision.
5. Update database to add a new azure subscription
    - Open `cmd/transitions/library/azure_subscription_data.yaml` and add the new subscription to the correct environment
    - Create a PR for the change and wait for build to go 🟢
    - Run the transition to add update the subscriptions in the environment
      `.transitions run <pull-request-url> <environment> --command azure_subscription_update.go`
      **optional:** Run over all our environments with -> `.transitions run <pull-request-url> * azure_subscription_update.go`
    - Monitor the transition for successful completion

    If transitions are failing you can do this manually: 

    > Manual:
    >   - We don't have an API for managing azure subscription because it is very rare operation. Also, we don't support automatic DB transitions in IMS. So, adding new azure subscriptions should be done manually via prod-shell and MySQL CLI
    >   - Steps:
    >       1. Connect to production shell: https://thehub.github.com/security/security-operations/production-shell-access/
    >       2. Connect to MySQL instance using connection data from https://professorx.githubapp.com/. Use `MYSQL_USER` and `MYSQL_PASSWORD` from Vault to get Write access to database
    >       3. Run SQL query to insert new azure subscription. Example:  
    >       `INSERT INTO azure_subscription (subscription_id, image_type, resources_prefix, image_versions_limit) VALUES ('16eb6e57-e88b-49c9-8acb-26048bee1f93', 'Customer', '1658309489', 10000)`
    >   - Notes:
    >       - `image_type` can be `Curated` or `Customer` depending on purpose of new azure subscription
    >         - For Proxima stamps the `image_type` should always be `customer` as they do not store curated images.
    >       - `resources_prefix` is generated in the previous step
    >       - `image_versions_limit` can be set to 1000 or 10000 depending on whether the exception from step 3 is applied to subscription or not. > If exception is applied and limits are bumped to 10k, we can use 10000. If exception is not applied or we are still waiting for it, we should use `1000` as 
    > value. This value can be updated for subscription later if needs

