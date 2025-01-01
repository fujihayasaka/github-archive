# Marketplace images in IMS

## Context

GitHub Actions provides Runners for different purposes (Basic X64, Arm64, GPU). Different customers' use-cases require using images with different pre-installed software:
- Some of these images are GitHub-owned (aka Curated), generated and managed by GitHub (see https://github.com/actions/runner-images).  
- Other images are provided by our partners (NVIDIA, Arm Inc) via Azure Marketplace.

As for the partner / marketplace images, GitHub doesn't have any control on image-generation process for such images and provide them as it is. Pre-installed software, security updates, bug fixing are on image owners.
Right now, we provide 13 azure marketplace on LHR. In future, we are planning to add more images with different Linux distributives and different use-cases.

## Marketplace images in Larger Runners service

How Azure Marketplace support is implemented in Runner service:
- The list of supported azure marketplace images is hardcoded in Runner service source code: https://github.com/github/actions-dotnet/blob/main/Runner/Service/Server/Images/MarketplaceImagesService.cs  
- All other image data (image definition properties, list of image versions, image version details) are retrieved from Azure on-demand and cached in-memory.  
- When Runner service creates virtual machine with marketplace image, it points to azure marketplace image directly using image reference:
    - `{ "id": "", "publisher": "canonical", "offer": "0001-com-ubuntu-server-jammy", "sku": "22_04-lts-arm64", "version":"1.0.0"}`
- After VM creation, Runner service using RunCommand to configure VM (install abuse tools, agent, apply some basic commands, etc).  
    - Also, some marketplace images require additional image-specific configuration. Sometimes, it takes much time.

**Known problems:**

Support for Azure Marketplace images was added to Runner service 2 years ago. During this time we identified a bunch of problems related to this approach.

- VM preparation for marketplace images takes more time than for curated images
    - For the most of marketplace images, commands are the same and pretty quick. They include configuring user, configuring docker, installing provjobd and agent. It takes less than 10s (p90)
    - There is at least one image which requires extra configuration. NVIDIA image requires applying GPU drivers on-flight and it takes ~1m.
    - Also, managing per-image vm preparation commands in Runner service is not convinient
- There is no easy way to rollback broken image version.
    - Since we consume images directly from Azure Marketplace, we don't have control on `latest` tag for these images. The current Runner implementation doesn't allow us to disable broken image version on our side
- There is no protection from removing image by image owner
    - Since image is owned by external people, there is a chance that image will be removed one day. It will immediately break and block all customers who use the deleted image.
    - It is pretty rare case but we faced with it once when NVIDIA removed old image without notice. We mitigated it by asking NVIDIA to restore image temporary and give us time to switch to new image.
- Retrieving image data from Azure and cache in-memory often causes performance problems
    - If in-memory cache is outdated, we have to perform sync call to Azure API to retrieve fresh information. Sometimes, such call can be very inefficient and cause performance problems with Runner API or other processes


## Proposal

### Option 1. Consume images directly from Azure Marketplace

With this option, we will implement the similar approach to what we have right now in Runner service. See details in section above.

During implementation, we will fix the following problems of current Runner implementation:
- We will use persistent storage (database) for storing azure marketpace images and image versions to avoid sync calls to Azure. Background cron job will refresh data in database with some cadence.
- Support rollbacks the similar way how it works for gallery image versions

Pros:
1. Minimal maintenance because images are consumed directly from Azure Marketplace

Cons:
1. VM preparation time
    - Marketplace images don't have pre-installed GitHub tools. Resource Provider will need to install abuse tools, HCA and actions agent. It will increase vm preparation time and QTA for marketplace images in comparison with curated images
    - As it was mentioned above, in some exceptional cases (GPU Runners), vm preparation will take up to 1m! It works for us on LHR but we want to improve it for 49s case.
    - Failures with pre-installing tools are a runtime issue, impacting the ability of customers to run jobs, if this was done at image generation it would only impact release of a new image, we would continue using the last known good image.
2. VM preparation compexity
    - As it was mentioned above, some marketplace images require special commands to configure image-specific things. These additional steps will need to be performed by Resource Provider but it doesn't make sense to store "steps per image" in RP. So, these additional steps will need to be stored in IMS and passed to Resource Provider with other information
3. Implementation complexity
    - This option requires a lot of implementation on IMS side. Database changes, API changes, background job, etc. It is significantly more difficult than Option 2.


### Option 2. Re-upload Marketplace images to Azure Gallery and treat them as Curated images

The main idea of this option is taking Azure Marketplace image, preparing it and then uploading to IMS as Curated image.

We will implement actions workflow which will perform the following steps via Azure API or Packer:
1. Create VM from original azure marketplace image
2. Run image preparations scripts on VM
3. Export VM disk as a new image
4. Upload prepared image to IMS as Curated image to Canary image definition
5. Run smoke tests on image
6. Upload prepared image to IMS as Curated image to Production image definition

Image preparation scripts will include:
- Cache HCA, abuse tools and actions agent
- Apply image settings
- Perform all image-specific preparation commands
- Auth into Docker
- Generate `imagedata.json` for Set up job step
- etc

After uploading image to IMS, it will be stored in Azure Gallery similar to any other curated images instead of Azure Marketplace.  
Resource Provider will create VM from the gallery image the same way as it works for curated images. Image will be ready to use, so RP won't need to do any extra configuration.

We will run the pipeline to prepare marketplace image and upload it to IMS in the following cases:
- when new version of source image is released
    - At the begin, we will configure notifications to let us know when new image version is released and needs to be uploaded. Later, we will consider automating image uploading to IMS when new image version is released for original image.
- on monthly basis
    - It is required because the most of Azure Marketplace images are updated pretty rare (once per 3-6 months). It means that GitHub tool cache (HCA, abuse tools, agent) can be outdated on image.
- on-demand by request

Also, we confirmed that this approach doesn't break image license. See https://github.com/github/CELA-product-counsel/issues/616#issuecomment-2616844509 for details

Pros:
1. Image version is ready to use for Resource Provider. No extra configuration required. RP will only need to run a couple of warm up commands which must be run on final VM.
2. Full control on new image version rollout and rollback
    - Existing flow for Curated images will work fine for Marketplace images.
3. Ability to customize images and deal with breaking changes
    - Sometimes, new versions of partner images can introduce breaking changes or bugs. This approach gives us flexibility to apply any specific patches to image during image preparation.
4. Easy implementation
    - All IMS logic are already in-place. We will only need to make tiny changes to distinguish curated github images form curated partner images
    - The most of required work will be related to creating pipeline for image preparation

Cons:
1. Maintenance of image preparation pipelines
    - This approach will require us to configure and maintaining a bunch of Actions workflows outside of IMS which will perform image preparation steps. Right now, it is 13 images. In future, the number of images will be increased to up to 50.
    - Maintenance of these workflows will require some effort from us. But it looks acceptable effort considering the advantages of this option. Also, we will make sure that our implementation is flexible enough to support more images in future.
    - Also, we don't expect many problems with image preparation steps because we will keep these scripts simple.
2. Manual uploading of new image versions
    - We will need to trigger image version preparation process when new image version is released. It will require some effort from GitHub engineer to trigger and monitor the process.
    - On the first stage, we will keep the trigger manual and will only configure notifications to let us know when new image version of marketplace image is released.
    - On long term, after confirming that process is stable enough, we will be able to fully automate this process and reduce effort.
3. Maintenance of Azure resources
    - Image preparation steps will require creating and maintaining some set of Azure resources.
    - It doesn't look like a problem because we will need to have and support the same set of resources for curated image generation. We will be able to re-use existing infrastucture.
4. Increasing image deployment time
    - Image preparation will take some time (15-60 minutes depends on image size). Delivery of new image versions will be increased by this time
    - It doesn't look like critical problem because marketplace image updates are released very rare (once per 3-6 months), so 1h image preparation time is acceptable.
5. Managing replications for partner images.
    - Replications for marketplace images are managed by Azure. If we upload prepared marketplace image to Azure Gallery, it will be on us to manage replications for such images.
    - It shouldn't be a problem because IMS already has replication job which manages replicas for curated images. All this logic will work from the box for marketplace images if they are uploaded to gallery.

#### Option 3. Image preparation via custom images flow

This option is pretty similar to Option 2. The only change - we can consider using "custom images as workflows" feature to generate curated images.
Potentially, it will help us to avoid maintenance resources and image preparation pipelines.

But this option doesn't feasible on short-term:
1. chicken-egg problem -> To prepare image via image-generation workflow, we need Resource Provider to create VM and assign job on it. But Resource Provider requires already prepared image to create VM from it.
2. generating curated images via workflow will require much changes in Runner service. It doesn't make sense to explore this option before we migrate image generation to 49s.
3. image generation workflow doesn't support some features required for image preparation (like reboot)
4. require much implementation effort in comparison with Option 2.


## Conclusion

Since we want to optimize vm preparation time and QTA, the option 1 doesn't look suitable.  
Options 2 and 3 are pretty similar and it will be cheap to switch between them in future.  

We would like to start with Option 2 for now. It will let us to migrate marketplace images in LHR to IMS quickly and unblock marketplace images for 49s.

> [!WARNING]  
> Unfortunately, neither of these options solve `There is no protection from removing image by image owner` problem.
> Even if build own image based on azure marketplace image, the generated image will depend on Azure plan of original image. If original image is removed by owner, our generated image will become broken and we won't be able to create VMs from it anymore.
> See investigation of this problem in https://github.com/github/hosted-compute-ims/issues/980
> If we want to solve this problem, we will have to contact Azure and ask for exception for Azure plan validation for us. If they agree to provide such exception, it will work with option 2 & 3.

