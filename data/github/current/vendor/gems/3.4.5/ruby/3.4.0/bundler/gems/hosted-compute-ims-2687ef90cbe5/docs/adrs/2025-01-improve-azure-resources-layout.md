# Change Azure Resources Layout to pack image versions more effectively

## Azure Limitations

The choice of Azure Resources layout is dictated by limitations which Azure has for Azure Compute Gallery and its child resources.

Azure has the following limitations:
> [!TIP]
> Azure has the following limits for Azure Compute Galleries resources:
> - 100 galleries, per subscription, per region
> - 1,000 image definitions, per subscription, per region
> - 10,000 image versions, per subscription, per region
>
> Learn more on https://learn.microsoft.com/en-us/azure/virtual-machines/azure-compute-gallery#limits

## Limits for users

Per discussion with product, we want to setup the following limits for users:
- 50 image definitions per user
- 50 image versions per image definition

## The current resources layout

Currently, IMS uses the following resources layout:

```
subscription/
└── resourceGroups/
    └── hostedcomputeims-1658309489/ 
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
- Every subscription contains the single resource group for all IMS resources.
- Resource group contains the single compute gallery (which contains images definitions and image versions of different users).
- Compute gallery contains up to 100 gallery image definitions. Every image definition is associated with specific IMS image and store all image versions of this image definition.
- Every Gallery image definition contains up to 100 image versions.
- Naming:
    - Resource group and gallery have name which is unique across all subscriptions
    - Gallery image definition has naming: `image-<image_definition_id>` (example: `image-1`)
    - Gallery image version has naming: `<version>` (example: `1.0.0`)

Conclusions of this approach:
- All image versions of specific image are stored in the same gallery in the same gallery image definition.
- Different images of the same user are spread across different subscriptions.
- Every image definition can have up to 100 image versions.
- Every user can have indefinite number of image definitions

## What is wrong with this approach?

This approach works fine for us on production right now. Also, our current layout satisfies the limits defined by product.

The only concern of current layout is efficiency of image versions packing.  
With this layout, we limit the number of image versions per image definition to 100 and one azure subscription can have 100 image definitions as maximum. This way, if users create 10k image definitions, we will need to have 100 azure subscriptions to store them.

It doesn't look to effecient because, on practice, the most of image definitions will have less than 100 image versions because:
- users don't really need so many image versions except some exceptional cases.
- users will have to pay for custom images storage, so the most of users would prefer to reduce cost.
- we will provide flexible retention policies to remove old image versions.

On practice, we expect the most of customers to have ~5-15 image versions. So, we will reserve 100 image versions slots for every image definition, but only 5-15 of them will be used.
As a result, we will lose a lot of free slots for image versions and over-provision the azure subscriptions.

## Proposal

Azure has recently bumped gallery image definition limit for us to 10k. So, both gallery image versions and gallery image definitions limit are equal for now.
It opens opportunity to utilize azure subscriptions more effectively and store 10k image versions on single azure subscription without losing free image version slots.

With the new approach, we will allow splitting image versions of specific IMS image definition between different azure subscriptions if already used subscriptions don't have free slots:
- Image version will be assigned to azure subscription instead of image definition. Every azure subscription will have 10k limit for image versions
- When assign a new image version to azure subscription, IMS will give higher priority to azure subscriptions which are already assigned to other image version of this IMS image definition
    - It will help to group image versions of the same image definition on the same azure subscription if possible (if subscription has free slot)
    - If already used subscription doesn't have free slots, a new azure subscription will be assigned to image version

We will keep the similar naming approach for azure resources (with tiny changes):
- `ResourceGroupName`: `hostedcomputeims-<URP>-rg`
- `StorageAccountName`: `ims<URP>`
- `StorageContainerName`: `vhds`
- `StorageBlobName`: `image-<ImageId>-<ImageVersion>.vhd`
- `GalleryName`: `imsgallery.<URP>`
- `GalleryImageDefinitionName`: `image-<ImageId>-<VmGen>`
- `GalleryImageVersion`: `<ImageVersion>`

Where:
- `<URP>` - Unique Resource Prefix of Azure Subscription. Ex: `1658309489`
- `<ImageId>` - Id of image definition. Ex: `1`
- `<ImageVersion>` - Version of image. Ex: `1.0.0`
- `<VmGen>` - VmGeneration of image. Ex: `gen1` / `gen2`

Main differences from previous naming:
- Adding `gen1`/`gen2` postfix to gallery image definition name
    - Currently, our service needs to support both vm generations of images. GH curated images are gen1 for legacy reasons. The most of marketplace and custom images are gen2.
    - Eventually, we will need to migrate curated images to gen2.
    - Adding vm generation to gallery image definition naming will allow us to mix image versions of `gen1` and image versions of `gen2` within the same IMS image definition. It will help us to perform smooth transition in future.
- Tiny renaming of RG name, gallery name and storage account name to ensure smooth transition from azure layout v1 to azure layout v2.

Example of azure resources structure with new naming:
```
subscription/
└── resourceGroups/
    └── hostedcomputeims-1658309489-rg/ 
        └── galleries
            └── imsgallery.1658309489
                └── imageDefinitions/
                    ├── image-1-gen1
                    │   └── imageVersions/
                    │       ├── 1.0.0
                    │       ├── 2.0.0
                    ├── image-1-gen2
                    │   └── imageVersions/
                    │       ├── 3.0.0
                    │       ├── 4.0.0
                    ├── image-2-gen1
                    │   └── imageVersions/
                    │       └── ...
```

Conclusions of new approach:
- With new azure resources layout, we will be able to utilize all 10k image versions slots on every azure subscription
    - With previous azure resources layout and 5-15 image versions per image (average usage), we were able to use ~500-1500 of image versions per azure subscription
    - With new approach, we will use 10k image versions in all cases. First edge case: 1 image with 10k image versions. Second edge case: 10k images with 1 image version. In both cases all slots will be effectively used.
- In the most of the cases, all image versions of specific image will be stored within the single azure subscription within the single image definition. If single azure subscription doesn't have enough slots, image versions will be spread across different azure subscriptions.
- This approach removes technical limitation on "count of image versions per image".
    - According to our discussion with product, we want to limit "count of image versions per image" to 50 and "count of images per account" to 50.
    - The new approach allows us to extend these limitations for specific user if necessary
