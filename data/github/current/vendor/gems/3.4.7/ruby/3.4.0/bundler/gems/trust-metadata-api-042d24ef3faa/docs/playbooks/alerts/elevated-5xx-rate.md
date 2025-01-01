# Elevated 5xx Rate

An alert has been triggered because the 5xx rate tracked by [`trust-metadata-api/elevated-5xx-rate`](https://app.datadoghq.com/monitors/104587269) has exceeded the currently defined threshold.

## Steps to Investigate

1. Check the [TMA Datadog Dashboard](https://app.datadoghq.com/dashboard/p5b-5gt-v76/trust-metadata-api) to see when the increased 5xx rate started.
1. Check whether there have been any recent deploys.
1. Check the GLB & Moda Kubernetes pod logs on the service's [Moda page](https://devportal.githubapp.com/apps/trust-metadata-api).
1. Check whether there are any ongoing events in the cluster where the service is deployed: [production general-1-ash1-iad cluster event page](https://devportal.githubapp.com/apps/trust-metadata-api/deployments/production/clusters/general-1-ash1-iad/events). See [here](https://devportal.githubapp.com/apps/trust-metadata-api/deployments/production/clusters/general-1-ash1-iad) for a list of cluster checks.
1. Check the [Splunk](https://splunk.githubapp.com/) logs for any noticeable errors. `index IN(trust-metadata) kube_namespace=trust-metadata-api-*`.
    1. For Proxima EU stamps, use this [Splunk](https://splunk-eu.githubapp.com/) instance, using `index IN(trust-metadata) kube_namespace=trust-metadata-api-*`.
1. Check whether there are ongoing issues with Azure Blob Storage. See [Microsoft Azure Status & Incidents](../../azure.md#microsoft-azure-status--incidents).
   1. If you are seeing an elevated number of sentry errors referencing a failure to upload or download blobs with the message "context was cancelled", try modifying the [Azure Blob Storage client timeout and retry configuration](https://github.com/github/trust-metadata-api/blob/9f55cdc1f2a58a9ed070ac80a2d25b4df3eb5b0b/pkg/storage/azureblob/remote.go#L56-L64).
   This message indicates that the TMA's request to blob storage stalled until timing out.
   1. Check the blob storage account's monitoring pages:
      - [Production monitoring insights page](https://portal.azure.com/#@githubazure.onmicrosoft.com/resource/subscriptions/56eeaa83-e372-4311-a873-55e3806dcc42/resourceGroups/TMA-Production/providers/Microsoft.Storage/storageAccounts/tmaproduction/insights)
      - [Staging monitoring insights page](https://portal.azure.com/#@githubazure.onmicrosoft.com/resource/subscriptions/a0231bbd-fed8-4abc-bc8d-dc92d3e358bf/resourceGroups/TMA-Staging/providers/Microsoft.Storage/storageAccounts/tmastaging/insights)
    1. Check if any changes to the blob storage infrastructure were deployed with Terraform.
      - [Production TFE](https://terraform.githubapp.com/app/package-security/workspaces/trust-metadata-api-production)
      - [Staging TFE](https://terraform.githubapp.com/app/package-security/workspaces/trust-metadata-api-staging)

