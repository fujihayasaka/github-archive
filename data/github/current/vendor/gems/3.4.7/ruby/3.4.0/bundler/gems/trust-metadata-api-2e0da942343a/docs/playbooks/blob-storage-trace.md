# Tracing Blob Storage Uploads and Downloads

To help us understand the impact attestation size has on the time
it takes to upload and download attestations from blob storage, we
have included custom logging in the 
[Azure blob storage client code](../../pkg/storage/azureblob/client.go) that includes the blob name and blob size in bytes.

These logs are sent to Splunk and are automatically tagged with the
associated span and trace IDs.

To understand how long the blob upload or download took, we can
look up the specific `Blob_StoreAttestation` and `Blob_DownloadAttestation`
spans in DataDog.

Navigate to the corresponding saved span search below and include `span_id:<your span ID>` in the search query.

- [Staging](https://app.datadoghq.com/apm/traces?saved-view-id=2826301)
- [Production](https://app.datadoghq.com/apm/traces?saved-view-id=2826302)

From here you can click into the `Blob_StoreAttestation` or
`Blob_DownloadAttestation` span you are interested in and
see how long it took the request took.
