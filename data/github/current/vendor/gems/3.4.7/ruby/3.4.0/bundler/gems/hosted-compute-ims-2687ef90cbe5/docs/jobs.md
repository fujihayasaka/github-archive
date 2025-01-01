# Jobs

There are two types of jobs in IMS:
- Worker jobs
- Cron jobs

## Worker jobs

Worker jobs are jobs which are run on-demand.
We use [Aqueduct](https://thehub.github.com/epd/engineering/github-internal-platform/data-streaming/aqueduct/) for worker jobs in IMS.

There are the following worker jobs in IMS:
- [ProvisionImageVersionJob](../internal/promotion/provision_image_version.go)
    - Job is queued by `CreateImageVersion` API call.
    - Job imports image from VHD URL to IMS service. Usually, importing image includes two steps: copying VHD image to IMS storage account and creating image version from VHD image.
- [ProvisionCleanupJob](../internal/promotion/provision_cleanup.go)
    - Job is queued in two cases: when `ProvisionImageVersionJob` job fails and resources should be cleaned up or when image version is deleted.
    - Job cleans up all Azure resources which are related to specific image version
- [DeleteImageVersionJob](../internal/promotion/delete_image_version.go)
    - Job is queued by `DeleteImageVersion` API call when image version is deleted
    - Job calls `ProvisionCleanupJob` under hood to clean up all Azure resources, then remove image version from database.

## Cron jobs

Cron jobs (aka background jobs) are jobs which are run on a repeating schedule (every N hours / every N minutes).
We use [Kubernetes CronJobs](https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/) for cron jobs in IMS.

There are the following cron jobs in IMS:
- [ReplicationJob](../internal/cronjobs/replication_job.go)
    - Job is run every 30 minutes
    - Job retrieves per-image usage statistic from Runner service and update replication regions and replicas count for Gallery Image Versions according to this data.
    