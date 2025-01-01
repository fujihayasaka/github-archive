[&lt;&lt; Spokes API](../../../README.md)

# spokes-api/blobs/v1/pushed_blob_item.proto



## Types

<a name="github.spokes.blobs.v1.PushedBlobItem"></a>

### PushedBlobItem
PushedBlobItem includes the oid, commit, path and size of a given blob.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| oid | [github.spokes.types.v1.ObjectID](../../types/v1/object_id.md#github.spokes.types.v1.ObjectID) |  | <p>oid is the object id of the blob.</p> |
| commit_oid | [github.spokes.types.v1.ObjectID](../../types/v1/object_id.md#github.spokes.types.v1.ObjectID) |  | <p>commit_oid is a commit that the blob was featured in.</p> |
| path | [github.spokes.types.v1.Path](../../types/v1/path.md#github.spokes.types.v1.Path) |  | <p>path is the first tree path the blob was associated with in the commit.</p> |
| size | [uint64](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | <p>size represents the full size of the blob.</p> |





