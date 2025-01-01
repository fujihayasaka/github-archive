# Exceptions Per Minute

An alert has been triggered because the application exceptions per minute tracked by [`trust-metadata-api/exceptions-per-minute`](https://app.datadoghq.com/monitors/102264107) has exceeded the currently defined threshold.

## Steps to Investigate

1. Check the [TMA Datadog Dashboard](https://app.datadoghq.com/dashboard/p5b-5gt-v76/trust-metadata-api) to see when the increased exceptions started.
1. Review the [TMA Sentry Dashboard](https://github.sentry.io/organizations/github/projects/trust-metadata-api) and investigate the exceptions that have been raised.
1. Check whether there have been any recent deploys that may need to be reverted.
1. Check whether there are ongoing issues with Azure Blob Storage. See [Microsoft Azure Status & Incidents](../../azure.md#microsoft-azure-status--incidents).
   1. If you are seeing an elevated number of sentry errors referencing a failure to upload or download blobs with the message "context was cancelled", try modifying the [Azure Blob Storage client timeout and retry configuration](https://github.com/github/trust-metadata-api/blob/9f55cdc1f2a58a9ed070ac80a2d25b4df3eb5b0b/pkg/storage/azureblob/remote.go#L56-L64).
   This message indicates that the TMA's request to blob storage stalled until timing out.
   1. Check the blob storage account's monitoring pages:
      - [Production monitoring insights page](https://portal.azure.com/#@githubazure.onmicrosoft.com/resource/subscriptions/56eeaa83-e372-4311-a873-55e3806dcc42/resourceGroups/TMA-Production/providers/Microsoft.Storage/storageAccounts/tmaproduction/insights)
      - [Staging monitoring insights page](https://portal.azure.com/#@githubazure.onmicrosoft.com/resource/subscriptions/a0231bbd-fed8-4abc-bc8d-dc92d3e358bf/resourceGroups/TMA-Staging/providers/Microsoft.Storage/storageAccounts/tmastaging/insights)
    1. Check if any changes to the blob storage infrastructure were deployed with Terraform.
      - [Production TFE](https://terraform.githubapp.com/app/package-security/workspaces/trust-metadata-api-production)
      - [Staging TFE](https://terraform.githubapp.com/app/package-security/workspaces/trust-metadata-api-staging)
