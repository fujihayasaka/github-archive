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





<a name="github.spokes.batch.v1.ReadRawDiffRequest"></a>

### ReadRawDiffRequest
ReadRawDiffRequest is the request body for reading raw diff requests.

```text
POST /streaming/v1/diffs/raw
Content-Type: [ application/json | application/protobuf ]
Accept: application/octet-stream

(ReadRawDiffRequest)
```


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| repository | [github.spokes.types.v1.Repository](../../types/v1/repository.md#github.spokes.types.v1.Repository) |  | <p>repository is the repository to operate on.</p> |
| request_context | [github.spokes.types.v1.RequestContext](../../types/v1/request_context.md#github.spokes.types.v1.RequestContext) |  | <p></p> |
| (oneof oid1) object_id1 | [github.spokes.types.v1.ObjectID](../../types/v1/object_id.md#github.spokes.types.v1.ObjectID) |  | <p>object_id1 selects an object by its OID.</p> |
| (oneof oid1) repo_object_id1 | [github.spokes.types.selectors.v1.RepoObjectIDSelector](../../types/selectors/v1/repo_object_id_selector.md#github.spokes.types.selectors.v1.RepoObjectIDSelector) |  | <p>repo_object_id1 selects an object by its OID that may exist in an alternate repository.</p> |
| (oneof oid1) root_selector1 | [github.spokes.types.selectors.v1.RootSelector](../../types/selectors/v1/root_selector.md#github.spokes.types.selectors.v1.RootSelector) |  | <p>root_selector1 selects the empty tree (from the root of the repository).</p> |
| (oneof oid1) parent_selector1 | [github.spokes.types.selectors.v1.ParentSelector](../../types/selectors/v1/parent_selector.md#github.spokes.types.selectors.v1.ParentSelector) |  | <p>parent_selector1 selects the parent of oid2.</p> |
| (oneof oid2) object_id2 | [github.spokes.types.v1.ObjectID](../../types/v1/object_id.md#github.spokes.types.v1.ObjectID) |  | <p>object_id2 selects an object by its OID.</p> |
| (oneof oid2) repo_object_id2 | [github.spokes.types.selectors.v1.RepoObjectIDSelector](../../types/selectors/v1/repo_object_id_selector.md#github.spokes.types.selectors.v1.RepoObjectIDSelector) |  | <p>repo_object_id2 selects an object by its OID that may exist in an alternate repository.</p> |
| full_index | [bool](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | <p>full index indicates whether to include the full index in the diff.</p> |
| mode | [ReadRawDiffRequest.DiffMode](#github.spokes.batch.v1.ReadRawDiffRequest.DiffMode) |  | <p>mode is the diff mode to use for the diff output.</p> |
| diff_algorithm | [github.spokes.types.v1.DiffAlgorithm](../../types/v1/diff_algorithm.md#github.spokes.types.v1.DiffAlgorithm) |  | <p>diff_algorithm is the diff algorithm to be used. If not specified, the default diff algorithm will be used.</p> |





<a name="github.spokes.batch.v1.ReadRawDiffRequest.DiffMode"></a>

### ReadRawDiffRequest.DiffMode
DiffMode specifies the format of the raw diff output.

| Name | Number | Description |
| ---- | ------ | ----------- |
| DIFF_MODE_INVALID | 0 | DIFF_MODE_INVALID is the default invalid value. |
| DIFF_MODE_PATCH | 1 | DIFF_MODE_PATCH generates output in patch format (similar to git format-patch). |
| DIFF_MODE_DIFF | 2 | DIFF_MODE_DIFF generates output in diff format (similar to git diff). |


