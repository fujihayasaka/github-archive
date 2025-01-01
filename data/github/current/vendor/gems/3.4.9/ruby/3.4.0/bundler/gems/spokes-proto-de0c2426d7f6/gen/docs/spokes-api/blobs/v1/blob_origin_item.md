[&lt;&lt; Spokes API](../../../README.md)

# spokes-api/blobs/v1/blob_origin_item.proto



## Types

<a name="github.spokes.blobs.v1.BlobOriginItem"></a>

### BlobOriginItem
BlobOriginItem holds the originating info for a given blob


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| blob_oid | [github.spokes.types.v1.ObjectID](../../types/v1/object_id.md#github.spokes.types.v1.ObjectID) |  | <p>blob_oid is the object id of the blob.</p> |
| commit_oid | [github.spokes.types.v1.ObjectID](../../types/v1/object_id.md#github.spokes.types.v1.ObjectID) |  | <p>commit_oid is a commit that the blob was featured in.</p> |
| path | [github.spokes.types.v1.Path](../../types/v1/path.md#github.spokes.types.v1.Path) |  | <p>path is the first tree path the blob was associated with in the commit.</p> |





