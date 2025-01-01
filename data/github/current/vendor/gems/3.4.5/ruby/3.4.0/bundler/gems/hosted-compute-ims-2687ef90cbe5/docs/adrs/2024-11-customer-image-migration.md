# Custom Image Migration to IMS

## Problem
We have customers that have custom images that are currently managed by the runner service. That service is going to be deprecated as we move to 4-9s and the image management part of it will be owned by the Image Management Service (IMS). That boils down to several problems that need solving as part of the migration.

1. Runner will need to be able to consume custom images from IMS in the short & medium term.
   * Runner will need to validate new pools are created with a valid image.
   * Runner will need to get the image reference for creating VMs.
   * Runner will need to be able to create new images and image versions as part of the custom image snapshotting feature.
2. We have existing customers that have have custom image definitions that are managed by runner and image versions that are also managed by runner. This problem is open to requiring some level of customer involvement as needed.


### Impacted Runner use cases
1. Custom Image REST APIs. [CustomImagesController](https://github.com/github/actions-dotnet/blob/840709bbfb6d7a5b153897e4e5fed8ef0ebc652e/Runner/Service/Api/Images/CustomImagesController.cs#L16) & [CustomImageVersionsController](https://github.com/github/actions-dotnet/blob/840709bbfb6d7a5b153897e4e5fed8ef0ebc652e/Runner/Service/Api/Images/CustomImageVersionsController.cs#L17)
    * These will need some level of forward or back compat as we move dotcom to consume IMS directly for these operations. 
    * These are built on top of methods in [IImageManagementService](https://github.com/github/actions-dotnet/blob/840709bbfb6d7a5b153897e4e5fed8ef0ebc652e/Runner/Service/Server/ImageManagementService.cs#L19)
        * CreateImageDefinitionAsync
        * GetImageDefinitionAsync
        * GetImageDefinitionVersionsSummaryAsync
        * GetImageDefinitionsAsync
        * GetImageDefinitionVersionsSummariesAsync
        * PendDeleteImageDefinitionAsync
        * GetImageVersionAsync
        * GetImageVersionsAsync
        * CreateAndImportImageVersionAsync
        * PendDeleteImageVersionAsync
2. [GetImageDetails](https://github.com/github/actions-dotnet/blob/840709bbfb6d7a5b153897e4e5fed8ef0ebc652e/Runner/Service/Server/ImageSourceInfo/CustomImageSourceInfoService.cs#L105) for pools on Custom Images.
    * We will need to support this general flow for the medium term in order for Runner to create VMs based on these custom images.
    * CustomImageSourceInfoService consumes [IImageManagementService](https://github.com/github/actions-dotnet/blob/840709bbfb6d7a5b153897e4e5fed8ef0ebc652e/Runner/Service/Server/ImageManagementService.cs#L19)
        * GetImageDefinitionAsync
        * GetImageVersionAsync
3. Custom Image snapshotting.
    * Same as GetImageDetails, this will need to continue to work as long as we support the Runner service.
    * Currently driven by ImageGenerationService.[CreateCustomImageFromRunnerVMAsync](https://github.com/github/actions-dotnet/blob/840709bbfb6d7a5b153897e4e5fed8ef0ebc652e/Runner/Service/Server/Images/ImageGenerationService.cs#L22)
    * [CreateCustomImageFromRunnerVMAsync](https://github.com/github/actions-dotnet/blob/840709bbfb6d7a5b153897e4e5fed8ef0ebc652e/Runner/Service/Server/Images/ImageGenerationService.cs#L22) consumes [IImageManagementService](https://github.com/github/actions-dotnet/blob/840709bbfb6d7a5b153897e4e5fed8ef0ebc652e/Runner/Service/Server/ImageManagementService.cs#L19)
        * GetImageDefinitionsAsync
        * GetImageVersionAsync
        * CreateImageDefinitionAsync
        * CreateImageVersionAsync
        * ImportImageVersionAsync
        * MonitorImageVersionCreationAsync

One thing that's relevant here is that all consumption of custom images eventually boils down to [IImageManagementService](https://github.com/github/actions-dotnet/blob/840709bbfb6d7a5b153897e4e5fed8ef0ebc652e/Runner/Service/Server/ImageManagementService.cs#L19).

### Solutions

The descision that we made was to go with option 2 as its considerably faster to develop and to roll out to production. The downsides of limited rollback isn't worth the investiment considering the considerably larger cost.

#### Option 1

##### Initial work
* Build a layer between the rest of the Runner service and IImageManagementService.
  * Update ImageKey to include new member that shows the source of the Image. ImageSource would work with values of either Runner or IMS. This solves the problem of knowing if an int (or long) is coming from tbl_ImageDefinition, or IMS.
  * Create a new implementation for IImageManagementService that is backed by IMS. (IImsImageManagementService)
  * Create a new default implementation for IImageManagementService that is backed by the merging of the one above (ultimately IMS) and Runner's implementation. IMergedImageManagementService
  * Rename current IImageManagementService to IRunnerImageManagementService
  * Move CustomImageSourceInfoService.TryGetImageDetailsAsync into IImageManagementService and at that scope it would know where the image details are actually coming from and return relevant data accordingly. Also, instead of returning image definition and image version, it would return the IImageArmTemplateDetails, which is what we actually need. This approach may also need to return the size because I don't think that's currently part of that interface.
  * If we have ImsImageId set for an image, image versions would be a union of Runner and IMS's image versions. We need to dedupe images and use IMS's image version if Runner and IMS have the same image.
* Update tbl_ImageDefinition to have an ImsImageId column that would get set at some point to use as a mapping.
* Create a fixed query that ensures for all image definitions that there is at least one enabled image version on IMS so that we can enable Image_Version_Ims_Only. 

##### Feature flag staged rollout
1. Image_Version_Read: IMergedImageManagementService: If tbl_ImageDefinition has an ImsImageId, Read from IMS, there should be no data and everything should continue to work as it does now. This will be used to roll back from using IMS for custom images quickly.
2. Image_Version_Favor_IMS: IMergedImageManagementService: When doing the merging of images returned by both Runner and IMS, this feature flag will switch which one we use for VM creations.
3. Image_Definition_Write: Backfill IMS Image Ids as needed for pools. This could be rolled out at the same time or even before the read feature flag. Also, double write image definition changes; the only changes that are relevant are the state transitions to deleting. 
4. Image_Version_Write: Double write image version updates to Runner and IMS. This could have a backill job that speeds the process up, but that is not required. More details in Migration of historical data.
5. Pool_ImageId_Read Update reads from tbl_Pool to use ImsImageId instead of ImageId. We'll use that for VM creations and other pool operations.
6. Image_Version_Ims_Only: Stop writing image definitions and image versions to Runner. At this point, new db writes should update ImageId in tbl_pool/tbl_VM to zero out the runner ImageId since we won't have it for new images.

* Once double write is stable, we could migrate dotcom's calls to IMS instead of effectively passing through Runner.

#### Migration of historical data

* This isn't required if all customers create a new image version after we've started at least doing double writes. If customers are consistently creating new image versions, that this is not neccessary.
* We create a job that backfills all images and image versions into IMS and keep checking until we have a swap over and manage a feature flag swap or something similar for the cut off. Prototype for that work is in this [draft PR](https://github.com/github/actions-dotnet/pull/18439/files). This would prevent blocking on customers running image version generation and would remove communication need if we did have to roll back and require new versions created multiple times.

#### Option 2

Create a job based on image definitions that does the following. This should be a one time job that gets queued and managed from a cmdlet.

* Takes the Runner image definition
* Create the same image definition in IMS
* Uploads all versions which were used for the last 7 days to IMS
* Set some registry value to say that this image is already migrated
* Update all pools which use this image to new Id (set old and new id side by side) but registry tells ImageManagementIdTranslator to use the new pool id.

If registry value is set "image is already migrated to IMS", all custom images API calls in Runner will call IMS API under hood and proxy details.
As soon as all images / all hosts are migrated, we will switch dotcom to use IMS API instead of using Runner as proxy.
CreateImageVersion/CreateImageDefinition calls will go through Runner to IMS as proxy.

APIs and CuratedImageSourceInfoService would need to check the feature flag and registry to know that which source of truth to use for a given image key.
When we switch to IMS image IDs as soon as everything is moved over, we can swap Runner to return and expect IMS image IDs and then immediately (or not) have dotcom start calling IMS for image related calls.

### Questions

What makes sure that when we switch the pool back and forth we have the right cached image id?
  - We need to set the registry key and then do a pool update which will restart the PSJ and ensure that we're on the correct version of the registry value.

#### Other options considered

We could skip double writes if we do the image migration job from the start and then we only need to read from both sources
* Upside: removes the need to ensure that uploading is successful to two locations at the same time.
* Downside: frontloads work that may not be required.

We could skip writing ImsImageId to tbl_ImageDefinition if we instead use the registry at the deployment level to create a mapping. This would work exactly like curated does today, where we'd use [ImageManagementIdTranslator](https://github.com/github/actions-dotnet/blob/8747919461b1fee1e3d485eb04a6ecfb91fa9e72/Runner/Service/Server/Images/ImageManagementIdTranslator.cs#L115) with the registry as the backing mapping location. This would be a little more difficult for figuring out what's migrated and what isn't since it wouldn't be directly in the table with the image definitions.

### Potential blockers / outstanding questions

We need IMS proxima stamps stood up prior to migrating custom images for Runner proxima stamps.
For GH/GH we will need to ensure that the replication job has run for the primary image that gh/gh uses prior to switching to use the IMS image version.
Do we need to prevent new image versions for a while after the swap to ensure that we don't have an expected roll back cause an unexpected customer image version rollback.
We should double check what the expected load on IMS will be after migration and also what the load on IMS will be for the migration.

# Additional Notes

In test, we have a problem where if we have an ImageId with ImageSource of Custom and ImageId of 2, we don't know if this is the RunnerImageId or the ImsImageId. When we switch our source of truth, we'll have objects in memory that we won't know where they came from. We need to solve this problem, probably by update ImageKey to indicate the source (DataSource or similar). Fixing this problem makes the translation when rolling out or rolling back feature flags easier to write without error.

There's no ImageDefintionRead since there's no value in reading from IMS for only image definitions until we've moved to not consuming Runner. The value we get from having the image definitions in IMS is for the image versions that'll be there. So, the first read feature flag is for image versions.

No matter what the implementation is, we should cache the image version details from IMS so that we don't need to get it every time.

We need to ensure that we've updated the telemetry to better understand where the image version is getting sourced from.

# Notes from sync review

* We have a fairly small number of pools and we can and should manage the rollout more hands on and manually through a cmdlet that drives the workload (even if the work should be done in a job)
* We need to update telemetry for migrated images in a way that's similar to what we've done for curated images (dashboards and etc should show the image source)
* Investigate migration load on IMS and the network
* Investigate post migration load on IMS and the network
* Follow up with product on thoughts here: Main feedback from product is to not roll back to Runner after we've migrated an image since that would cause temporary data loss and being down for updates to an image would be better than data loss.

### Existing helpful components

1. Runner has a service for getting the [global id for a Runner host](https://github.com/github/actions-dotnet/blob/7180a38ff92132114ae1068f6ba2cd90440ef9b8/Runner/Service/Server/ImageSourceInfo/ImageManagementSourceInfoService.cs#L44).
