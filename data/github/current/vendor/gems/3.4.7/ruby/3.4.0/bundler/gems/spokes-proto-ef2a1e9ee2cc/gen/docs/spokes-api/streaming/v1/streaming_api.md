[&lt;&lt; Spokes API](../../../README.md)

# spokes-api/streaming/v1/streaming_api.proto



## Types

<a name="github.spokes.batch.v1.BatchBlobsRequest"></a>

### BatchBlobsRequest
BatchBlobsRequest is the request body for batch blob requests.

```text
POST /streaming/v1/blobs
Content-Type: [ application/json | application/protobuf ]
Accept: application/tar

(BatchBlobsRequest)
```


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| repository | [github.spokes.types.v1.Repository](../../types/v1/repository.md#github.spokes.types.v1.Repository) |  | <p>repository is the repository to scope the blob to.</p> |
| request_context | [github.spokes.types.v1.RequestContext](../../types/v1/request_context.md#github.spokes.types.v1.RequestContext) |  | <p></p> |
| oids | [github.spokes.types.v1.ObjectID](../../types/v1/object_id.md#github.spokes.types.v1.ObjectID) | repeated | <p>oids are the OIDs of the blobs to return.</p> |
| filters | [BlobFilter](blob_filter.md#github.spokes.batch.v1.BlobFilter) |  | <p>(Optional) Filter blobs before they are returned.</p> |





