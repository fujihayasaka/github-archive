# Azure Subscriptions

IMS service uses Azure subscriptions to create and manage resources related to images: [resource groups](https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/manage-resource-groups-portal), [storage accounts](https://learn.microsoft.com/en-us/azure/storage/common/storage-account-overview), [compute galleries](https://learn.microsoft.com/en-us/azure/virtual-machines/azure-compute-gallery).

Available Azure subscriptions are stored in the [azure_subscription](https://github.com/github/hosted-compute-ims/blob/e7c27cd71698e69eb60279d1fbe41c49ddf66b10/db/schemas/tables/azure_subscription.sql) database table and every image definition is assigned to one of the subscriptions.

## Pre-requirements for New Azure Subscriptions

New Azure Subscriptions are not required to pre-create any special resources. All required resources (resource groups, storage accounts and galleries) will be created by IMS on demand (for example, storage account and storage container will be created during the first promotion phase)

We must make sure that the IMS service (or any dev accounts) have the following roles on every subscription:
- `Owner` (aka `Subscription Owner`) - required to manage resource groups and galleries.
- `Storage Blob Data Owner` - required to manage storage accounts.  

**Note:**  Although the `Owner` role permission grants full access to manage resources, it does not include permissions to access Azure Storage containers and blobs. Therefore the `Storage Blob Data Owner` role must be assigned separately.

## Development Environment

We use the following Azure subscription for local development: `VCFP_Eng` (`16eb6e57-e88b-49c9-8acb-26048bee1f93`).
It is assigned to the service via the database subscription seed script `db/seed/seed_azure_subscription.sql`

The following azure resources layout is used for the development environment:
```
/subscription/<subscription_id>
    /resourceGroup/hostedcomputeims-<github-handle>
        /storageAccounts/imsstorage<github-handle>
            /containers/image105                         <- 105 is image definition Id
                /imageVersions/1.0.0.vhd                 <- 1.0.0 is image version
        /galleries/imsgallery<github-handle>
            /imageDefinitions/image105                   <- 105 is image definition Id
                /imageVersions/1.0.0.vhd                 <- 1.0.0 is image version
```

where `<github-handle>` is unique GitHub alias of a developer. It is set via the `$GITHUB_USER` environment variable which is pre-configured within a Codespace environment.

## Lab and Production Environments

> [!TIP]
> Azure has the following limits for Azure Compute Galleries resources:
> - 100 galleries, per subscription, per region
> - 1,000 image definitions, per subscription, per region
> - 10,000 image versions, per subscription, per region
>
> Learn more on https://learn.microsoft.com/en-us/azure/virtual-machines/azure-compute-gallery#limits


The following resources layout is used for the production environment:

```
githubazure/
└── subscription/
    └── GitHub Hosted Compute IMS - Prod - 001/
        └── resourceGroups/
            └── hostedcomputeims-1658309489/ 
                │
                ├── storageAccounts
                │   └── imsb1658309489
                │       └── containers/
                │           └── image-1
                │               └── blobs/
                │                   └─ 1.0.0.vhd
                └── galleries
                    └── imsgallery1658309489
                        └── imageDefinitions/
                            ├── image-1
                            │   └── imageVersions/
                            │       ├── 1.0.0
                            │       ├── ...
                            │       ├── ...
                            │       └── 100.0.0
                            ├── image-N...
                            └── image-100
```

Notes:
- Storage account name and gallery name must be unique across Azure so we need to generate unique names for resources for every subscription.
    - Unfortunately, Azure has very strict limitations for naming for some resources (for example, storage account names must be 3-24 symbols and comprised of only lowercase letters and numbers). This is why we can't use the Azure Subscription Id directly as a unique identifier for our resources
    - We use unique numeric id generated as 32-bit FNV-1a hash of an Azure Subscription Id. On layout above, it is `1658309489`
- The separate storage container and Compute Gallery Image Definition are created for every image definition. Their naming is `image-<image_definition_id>`
- The name of VHD blob in storage container is `<image_version>.vhd`
- The name of Compute Gallery Image Version is `<image_version>`

Conclusions:
- According to this layout:
    - every azure subscription can be used to store 100 image definitions. Every image definition can have 100 image versions as maximum.
    - all image versions which belongs to specific image definition are stored in the same Compute Gallery Image Definition.
    - image definitions of specific customer can be spread across different azure subscriptions
- It gives us the following limits:
    - Customer's image definition can't have more than 100 image versions. It is hard limit of our service which can't be overcome.
    - Customer can have unlimited number of image definitions.

> [!NOTE]  
> Per discussion with product, we are fine to limit the number of image definitions per customer and the number of image versions per image definition to 100.
> 100 image versions per image definition is pretty huge limit:
> - Our current limit in Runner service is 20 image versions per image definition.
> - If customer generates image every day, 100 limit will be enough to store images for the last 3 months. Per product suggestion and security concerns, we want to restrict customers to use custom images older than 1 month.
