[&lt;&lt; Spokes API](../../../README.md)

# spokes-api/blobs/v1/reachable_blob_item.proto



## Types

<a name="github.spokes.blobs.v1.ReachableBlobItem"></a>

### ReachableBlobItem
ReachableBlobItem includes the oid, commit and path of a given blob.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| blob_oid | [github.spokes.types.v1.ObjectID](../../types/v1/object_id.md#github.spokes.types.v1.ObjectID) |  | <p>blob_oid is the object id of the blob.</p> |
| commit_oid | [github.spokes.types.v1.ObjectID](../../types/v1/object_id.md#github.spokes.types.v1.ObjectID) |  | <p>commit_oid is a commit that the blob was featured in.</p> |
| path | [github.spokes.types.v1.Path](../../types/v1/path.md#github.spokes.types.v1.Path) |  | <p>path is the first tree path the blob was associated with in the commit.</p> |
| mode | [github.spokes.types.v1.Mode](../../types/v1/mode.md#github.spokes.types.v1.Mode) |  | <p>mode is the file mode of the blob.</p> |
| status | [github.spokes.types.v1.DiffStatus](../../types/v1/diff_status.md#github.spokes.types.v1.DiffStatus) |  | <p>status is the status of the blob.</p> |





