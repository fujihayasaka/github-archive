For development:

Download the [Microsoft Azure Storage Explorer](https://azure.microsoft.com/en-us/features/storage-explorer). You will have to manually add a local connection (use the plug icon on the left), and the ports are the only non-default configuration you need to change. If you're running locally, the ports are changed to 20100 / 20101 / 20102, but if you're in a codespace you will need to configure a remote connection with the same connection string we use for things like tests (as of the time of this writing it's the default value that is in config.AzureStorageBlobEndpoint).

For production:

If you're trying to inspect blobs manually or debug things through the azure portal, start by heading [here](https://portal.azure.com/#@githubazure.onmicrosoft.com/resource/subscriptions/e98e5af3-7319-4357-9296-0f572fc85b0b/resourceGroups/ds-api-production/providers/Microsoft.Storage/storageAccounts/proddssnapshotsstorage/storagebrowser) and logging in with your @githubazure.com account.

The `snapshot-blobs` container is where all snapshots are stored (you can access it by clicking the "Blob Containers" button in the view the above link opened), and the file structure is `<repositoryID>/<snapshotUUID>` -- if you're looking for a particular snapshot, you probably first want to find it's row in the database (via `ds_snapshot_blobs`) but you can examine the URL to infer the `<repositoryID>/<snapshotUUID>` to navigate to.
