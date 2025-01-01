## Migrating Marketplace Images from Runner

We'll roll out each feature flag one at a time through all rings and in this order to move from marketplace images to IMS curated images. The image source will be the same for each, but the IMS curated images will have some tools cached for faster startup times and reduced service complexity.

[Feature flags](https://github.com/github/actions-dotnet/blob/2f12a3407c0e4f024f005a55c05cfc5aca10891c/Runner/Service/Servicing/Host/Deployment/Groups/RunnerFeatureAvailability.xml#L75-L79)

### Step 0 - Create images in IMS and create migration mappings.

Like we did for curated images, we need to create mappings for test and development images. Here's the [link](https://github.com/github/actions-dotnet/blob/2f12a3407c0e4f024f005a55c05cfc5aca10891c/Runner/Service/Server/StepPerformers/RunnerStepPerformer.cs#L128) for the curated mappings.

This is expected to have no impact.

### Step 1 - Enable for use in deployment

* `GitHub.Actions.Runner.Server.ImageManagementService.Marketplace`

Enable this and it will start checking to see what mappings exist in the registry to attempt to use them for deploying VMs, but if they don't exist, it will fall back to using the regular marketplace images.

This is where I'd expect to see some impact. The images are changing, which can cause impact to customer workflows.

### Step 2 - Translate the mappings from the database

* `GitHub.Actions.Runner.Server.ImageManagementService.Marketplace.TranslateFromDatabase`

If this is on, when runner reads an Image ID from the database, it'll turn that into an IMS Image ID before it leaves the component layer. This increases the scope that we use these IDs, but after migrating curated images, this should be low risk if step 1 was successful. 

This is expected to have no impact.

### Step 3 - Backfill database

* `GitHub.Actions.Runner.Server.ImageManagementService.Marketplace.BackfillDatabase`

If this is on, in pool sync job, runner will check to see if ImsImageId is set for the pool that's running the PSJ and if it isn't it'll do a no-opt write in order to backfill that data.

This is expected to have no impact. We won't be reading them until the next step, so it should be a quick and no impact rollout.

### Step 4 - Read from database

* `GitHub.Actions.Runner.Server.ImageManagementService.Marketplace.ReadFromDatabase`

If this is on, runner will read from ImsImageId instead of ImageId when reading the ImageId.

This is expected to have no impact. We're already using the IMS IDs from 2 in the Job Agent, so this shouldn't cause any impact.

### Step 5 - Update our APIs to use the new IDs

* `GitHub.Actions.Runner.Server.ImageManagementService.Marketplace.TranslateForApi`

If this is on, runner will return IMS Image IDs to dotcom instead of runner Image IDs.

This is expected to have no impact. When we drove this migration for curated, this had no impact, so we should be covered already for marketplace images.
