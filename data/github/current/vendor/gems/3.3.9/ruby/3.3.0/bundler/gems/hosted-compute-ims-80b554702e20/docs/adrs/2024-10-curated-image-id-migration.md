## Curated Image ID Migration

### Problem 

We need to move the source of truth for image IDs from Runner (3-9s) to IMS (4-9s) and in doing so we'll convert from a string based image ID to a ulong based image ID. We need to be online for the transition and be able to roll back from any stage to the previous stage (unless stated), so the goal is to do the bulk of the migration under feature flags that can be easily rolled back until we build enough confidence to change data.

## Proposal

A and B should be async from each other.

### Batch 0 (required for helping both flows be async from each other)
1. Update ImageManagementIdTranslator to not attempt multiple translations. IE, if we already have an IMS image ID, we should not attempt to translate that again to an IMS image ID.

### Batch 1a (setup: IMS_image_ID_S2S)
At the end of this batch dotcom and Runner can talk using either format.

1. Update Runner controllers to be able to work with both image IDs and be able to return either image ID based on a feature flag (IMS_image_ID_S2S) to roll forward to IMS image IDs. This would require compat work in the following places to translate IMS image IDs to Runner Image IDs. This should consume ImageManagementIdTranslator in order to drive the translation.
    * PoolsController.CreatePoolAsync
    * PoolsController.UpdatePoolAsync
    * CuratedImagesController.GetCuratedImagesAsync
2. Update dotcom to be able to use the image ID that it gets from runner regardless of if its a runner or IMS image ID.

### Batch 1b (setup: IMS_image_ID_DB)
At the end of this batch we treat the database as is if was already changed to using IMS image IDs.

1. Update CuratedImagesService.m_curatedImages in Runner to work with IMS image IDs and existing Runner image IDs.
   * CuratedImageLabelDefinition.s_imageIdToImageLabelMapping is intentionally skipped as it should not need to be used in the IMS focused flow.
2. Update prc_GetImageVersionUsage to check for both formats of the image ID.
3. Based on a feature flag update RunnerComponent.PoolColumns to translate from the current in database Runner image ID to IMS image ID but also update RunnerComponent to ensure that we don't save that IMS image ID to the database on writes.
4. Create a new column in tbl_VM and tbl_Pool that'll be the new image id column. We'll move to this when we switch over, while this isn't required for curated images, it will help for custom when we do a integer to integer translation and help with understanding what the source of truth is for that integer.
  * We should not write to this because of the feature flag in 3, but we should read from it and if its non-empty, use that value instead of the old column.
  * The code to write should exist behind the feature flag from 3 to reduce the work done in batch 3b and to help create unit tests for the end to end flow of the transition.

### Batch 2a (IMS_image_ID_S2S)
At the end of this batch dotcom and Runner talk using IMS image IDs.

1. Enable feature flag IMS_image_ID_S2S ring by ring.

### Batch 2b (Binary only: IMS_image_ID_DB)
At the end of this batch Runner treats all of its database data as if it were already updated.

1. Enable feature flag IMS_image_ID_DB ring by ring.

### Batch 3a (dotcom switch: IMS_image_ID_S2S)
At the end of this batch, we should treat IMS as the source of truth for curated image IDs.

1. Update dotcom to be able to switch its calls for getting image information from IMS instead of calling CuratedImagesController.GetCuratedImagesAsync.
2. Add tracing in Runner for consumers of the old image ID so that we can see the requests drain prior to removing the compat code. (AT&T is in closed alpha for public APIs) This should be done in the following places:
   * PoolsController.PoolCreateAsync
   * PoolsController.PoolUpdateAsync
   * CuratedImagesController.GetCuratedImagesAsync

### Batch 3b (DB change: IMS_image_ID_DB)
At the end of this batch all tbl_Pool and tbl_VM entries in runner should use IMS image IDs for curated images

1. Remove the check that stops us from writing the IMS image ID to the database in the RunnerComponent.
2. Create host upgrade step that reads the pool and then saves the pool with a no-opt update.

### Wait
Some level of waiting should be done here to ensure we don't need to roll back for any reason. 2-4 weeks should work.

### Batch 4a (finalize: IMS_image_ID_S2S)
Remove compat code.

0. Verify that all requests are using IMS image IDs. AT&T is in closed alpha to use public APIs and may still be using old image IDs. Tracing should have been added above for this.
1. Remove CuratedImagesController.GetCuratedImagesAsync
2. Remove compat in
   * PoolsController.PoolCreateAsync
   * PoolsController.PoolUpdateAsync

### Batch 4b (finialize: IMS_image_ID_DB)
Remove compat code.
1. ImageManagementIdTranslator should no longer be used since everything top to bottom should be on IMS image IDs. It should be removed and code flows that consume it should be behind feature flags that can be removed.
2. Remove CuratedImageIds since it should no longer be used.
3. We cannot remove the old column from tbl_VM and tbl_Pool because they'll still be used for custom images, but that upgrade should build on the work done here easily.
