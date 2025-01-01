# Images Overview in Runner service

Runner service support [3 types of images](https://github.com/github/actions-dotnet/blob/main/Runner/Shared/Common/ImageSource.cs#L10)
- [Marketplace](https://github.com/github/actions-dotnet/blob/main/Runner/Service/Server/Images/MarketplaceImage.cs) - images provided by Azure Marketplace.
- [Curated](https://github.com/github/actions-dotnet/blob/main/Runner/Service/Server/Images/CuratedImage.cs) (aka GitHub-owned) - images provided to us by image generation team + some other internal GitHub images (like Codespace-prebuild)
- [Custom](https://github.com/github/actions-dotnet/blob/main/Runner/Service/Server/Images/CustomImage.cs) - images provided by customers. Customers can provide us link to image in VHD format and we will import it to our system

## Curated images

The list of Curated Images is hardcoded in [CuratedImagesService](https://github.com/github/actions-dotnet/blob/main/Runner/Service/Server/Images/CuratedImagesService.cs) and can be changed only manually with Runner service deployment. Some images are hidden under FFs which can be enabled per user.

There are `ubuntu-latest` and `windows-latest` images. These images are [just pointers](https://github.com/github/actions-dotnet/blob/b9705b0fb6bc12b6c93b25bac6fdf9e5731de3e9/Runner/Service/Server/Images/CuratedImagesService.cs#L29) which redirect to some specific image os like Ubuntu 20.04 or Windows 2022.

Curated images and curated image versions are not stored in database. The source of truth for infomation about curated image versions is Azure. Azure calls are very expensive so we use cache in [CuratedImageVersionService](https://github.com/github/actions-dotnet/blob/main/Runner/Service/Server/Images/CuratedImageVersionService.cs) and [CuratedImageDetailsService](https://github.com/github/actions-dotnet/blob/main/Runner/Service/Server/Images/CuratedImageDetailsService.cs) to avoid extra calls to Azure.


Every Runner scale unit has own Azure Gallery with curated images.
Image-generation team builds images on weekly basis and upload generated images to special shared Azure Gallery. Then Runner service runs [CuratedImageCopyJob](https://github.com/github/actions-dotnet/blob/main/Runner/Service/Server/Jobs/CuratedImages/CuratedImageCopyJob.cs) every hour on every scale unit to copy the image from shared gallery to scale unit gallery.

Also, we have [CuratedImageReplicationManagementJob](https://github.com/github/actions-dotnet/blob/main/Runner/Service/Server/Jobs/CuratedImages/CuratedImageReplicationManagementJob.cs) which configure replication for every image version.

Find more info about curated images promotion and replication in [Curated Images](../curated-images.md) article.

## Custom images

The list of custom images and custom image versions is stored in database. See [tbl_ImageDefinition](https://github.com/github/actions-dotnet/blob/main/Runner/Service/Sql/Runner/Tables/tbl_ImageDefinition.sql) and [tbl_ImageVersion](https://github.com/github/actions-dotnet/blob/main/Runner/Service/Sql/Runner/Tables/tbl_ImageVersion.sql). Database is source of truth for custom images information and we avoid making expensive Azure calls to retrieve image information.

We don't configure replications for custom images for now. But potentially, we should.

Promotion of custom images:
1. Custom provides us an URL to VHD image
2. Runner service creates a new image definition (if it doesn't exist yet) and new image version in database and trigger two jobs:
3. [ImageDefinitionSyncJob](https://github.com/github/actions-dotnet/blob/main/Runner/Service/Server/Jobs/CustomImages/ImageDefinitionSyncJob.cs) - This job creates image definition in Azure Gallery.
4. [ImageVersionSyncJob](https://github.com/github/actions-dotnet/blob/main/Runner/Service/Server/Jobs/CustomImages/ImageVersionSyncJob.cs) - This job takes VHD URL and copy image from this URL to Azure Blob Storage. Then it creates Azure Image based on copied VHD and create Azure Gallery image based on Azure image.
5. Mark image as ready in database and new VMs start to use the new image

Also, there is [ImageVersionCleanupJob](https://github.com/github/actions-dotnet/blob/main/Runner/Service/Server/Jobs/CustomImages/ImageVersionCleanupJob.cs) job which is run once per day and check every custom image definition to see how many images are uploaded, keep last N images and remove older ones.

## Azure Marketplace images

In Runner service, we provide customers some images from [Azure Marketplace](https://azuremarketplace.microsoft.com/en-gb/marketplace/apps?filters=virtual-machine-images&page=1). Theses images are owned and uploaded to marketplace by other people and we only provide them for our customers.

The list of available Marketplace images is hardcoded in [MarketplaceImagesService](https://github.com/github/actions-dotnet/blob/main/Runner/Service/Server/Images/MarketplaceImagesService.cs) and all images are hidden under FFs.

Azure is source of truth for these images so we use caching in [MarketplaceImageVersionService](https://github.com/github/actions-dotnet/blob/main/Runner/Service/Server/Images/MarketplaceImageVersionService.cs) and [MarketplaceImageDetailsService](https://github.com/github/actions-dotnet/blob/main/Runner/Service/Server/Images/MarketplaceImageDetailsService.cs) to avoid expensive Azure calls.

No jobs or other complications around Marketplace images.

## What Runner service needs to know to create a VM with specific image and image version?

Runner service uses [Azure Deployment template](https://github.com/github/actions-dotnet/blob/b9705b0fb6bc12b6c93b25bac6fdf9e5731de3e9/Runner/Service/Server/Templates/vmResources.bicep) to create a new VM.

The most important property is `imageReference`. [ImageReference](https://github.com/github/actions-dotnet/blob/b9705b0fb6bc12b6c93b25bac6fdf9e5731de3e9/Runner/Service/Server/ArmContracts/ImageReference.cs) is an object which contains all properties to reference specific image and image version:
```json
"imageReference": {
    "id": "string",
    "offer": "string",
    "publisher": "string",
    "sku": "string",
    "version": "string"
}
```

`ImageReference` is built by [ImageSourceInfoService](https://github.com/github/actions-dotnet/tree/b9705b0fb6bc12b6c93b25bac6fdf9e5731de3e9/Runner/Service/Server/ImageSourceInfo) service based on `CuratedImageService`, `MarketplaceImagesService` and `CustomImagesService` which we mentioned above.

`ImageSourceInfoService` can answer on two questions:
- Give me image reference for image definition X and image version Y
- Give me image reference for image definition X and latest image version


Another case when Runner service needs to know about images is [PoolBusinessLogicService](https://github.com/github/actions-dotnet/blob/b9705b0fb6bc12b6c93b25bac6fdf9e5731de3e9/Runner/Service/Server/PoolBusinessLogicService.cs). This service validates pool properties and need to know image info (image size, image os) to validate that all properties of pool are setup correctly and don't conflict with each other.


## Rollback of images

All pools with Curated image uses latest image version. It means that all Vms will start using a new image version immediately when promotion is finished.
But there could be a situation when new image is broken or some pre-installed software is broken.

In such situation, we have an ability to rollback image via [UndoCuratedImageVersionCmdlet](https://github.com/github/actions-dotnet/blob/main/Runner/Tools/PowerShell/Cmdlets/UndoCuratedImageVersionCmdlet.cs) LR cmdlet. This cmdlet will enable "Exclude from latest" flag for image in Azure Gallery. And then `ImageSourceInfoService` will start to ignore the image version when look for "latest" image version.

# Future of Images service

[Images service functionality is still under discussion so it is just high level thoughts]

1. Focus on Image Management only (uploading, promotion, preparing for us, providing API) and follow single responsibility principle
2. Image Management service is image provider and should know nothing about images consumers
3. Follow 4-9s architecture and best practices:
    - Redis - cache with 5-9s reliability
    - Cosmos DB - NoSQL database with 5-9s reliability
    - Deployment - Moda, Kubernetes
    - Environments - dev (Codespace), lab, load, internal, production
    - Use dotcom FFs via twirp client
3. First phase - replication of existing functionality of Runner service with some improvements and integrating new service with Runner
4. More features on next phases:
    - Deployment plan for new image versions and os rollout
    - macOS images support (MacCloud V2 and MacCloud V3)
    - Integration with custom images feature or image generation service
    - Image specialization / image optimization


First questions:
1. How do we want to store images in a new service? (hardcode approach vs database). What will be database structure and what data do we need to store?
2. Can we unify curated and custom images as much as possible?
3. What image flow and image states will we have? (Queued, Copying, Importing, Ready to use). Make sure that our approach is flexible enough to be extended in future with additional steps like optimization and etc.
4. How images service will communicate with Runner / LCM / GCAS? Can we avoid direct API calls and use shared DB or Redis?
5. How can we ensure that GCAS / LCM / Runner continue to work even if Image Management service is down?
6. How will Image Managemenent service deal with long operations and handle random connectivity issues?
7. How will we synchronize multiple instances of Image Management service to make sure that we don't have race condition for long running operations?