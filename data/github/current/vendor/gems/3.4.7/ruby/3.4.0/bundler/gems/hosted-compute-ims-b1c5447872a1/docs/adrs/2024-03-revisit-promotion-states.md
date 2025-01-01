# Revisit promotion states

## Status
Accepted

## Context

During initial implementation of the promotion process in IMS, we implemented the same approach currently used by the Runner service:
1. When customer uploads a new image version, image version is created in database in "CopyImage" state
2. Worker picks up image in "CopyImage" state, copies it to storage account and updates image version state to "CreateImageVersion"
3. Worker picks up image in "CreateImageVersion" state, creates an Azure Compute Gallery Image Version from it and updates image version state to "Ready"

After using this approach for a couple of months, we noticed several drawbacks:
- No easy way to understand how many images are currently in the worker queue and waiting to be picked up as new image versions are created in "CopyImage" state
- No easy way to calculate the total promotion duration of image versions. To calculate the total promotion duration for a specific image version we need to sum the duration of the `CopyImage` job and subsequent `CreateImageVersionJob`
- Promotion duration is not predictable. Since the promotion process is split into two steps, there is no guarantee that the second step will be started immediately after the first one. Theoretically, there could be the situation when the first step is finished for N image versions but the second step is not started for these images because all workers are busy


## Proposal

1. Add a new state `Pending`.
    - This state will be used for a new image version entry in database. It means that the promotion process for an image version has not started yet
2. Merge "CopyImage" and "CreateImageVersion" promotion steps into the single step "Provisioning"
    - Promotion steps are idempotent so merging steps into the single one won't complicate retries. If create image version fails, we will restart the full job and it will skip copy image step
    - We will still be able to save progress details (CopyImage / CreateImageVersion) to `StateDetails` and track details to telemetry

This proposal should solve all drawbacks of current approach:
- We will be able to query all images in `Pending` state to figure out queue depth
- We will be able to track promotion duration as job duration
- Promotion process will be predictable because creating an image version will start immediately after a successful copy image