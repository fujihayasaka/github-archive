[&lt;&lt; Spokes API](../../../README.md)

# spokes-api/blobs/v1/blobs_api.proto



## Services

<a name="github.spokes.blobs.v1.BlobsAPI"></a>

### BlobsAPI

BlobsAPI contains APIs for blob-related Git operations.

<a name="github.spokes.blobs.v1.BlobsAPI-GetBlobContents"></a>

#### GetBlobContents

GetBlobContents returns the first megabyte of a blob specified by its oid.

##### Dev URL

`http://127.0.0.1:8081/twirp/github.spokes.blobs.v1.BlobsAPI/GetBlobContents`

<a name="github.spokes.blobs.v1.GetBlobContentsRequest"></a>

##### GetBlobContentsRequest




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| repository | [github.spokes.types.v1.Repository](../../types/v1/repository.md#github.spokes.types.v1.Repository) |  | repository is the repository to scope the blob to. |
| request_context | [github.spokes.types.v1.RequestContext](../../types/v1/request_context.md#github.spokes.types.v1.RequestContext) |  |  |
| (oneof blob) by_id | [github.spokes.types.v1.ObjectID](../../types/v1/object_id.md#github.spokes.types.v1.ObjectID) |  | by_id is the object id of the blob. |
| (oneof blob) by_ref_path | [GetBlobContentsRequest.RefPath](#github.spokes.blobs.v1.GetBlobContentsRequest.RefPath) |  | by_ref_path is a ref and path to select. |
| (oneof blob) by_object_id_path | [GetBlobContentsRequest.ObjectIDPath](#github.spokes.blobs.v1.GetBlobContentsRequest.ObjectIDPath) |  | by_object_id_path is an object ID and path to select. The Object ID must be resolvable to a tree (commit ID, tree ID, or tag ID). |



<a name="github.spokes.blobs.v1.GetBlobContentsResponse"></a>

##### GetBlobContentsResponse

GetBlobContentsResponse includes the full contents of the blob.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| contents | [bytes](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | contents is up to the first megabyte of the blob contents. |
| size | [uint64](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | size is the full size of the blob contents. |
| truncated | [bool](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | truncated is used to indicate whether the blob contents were truncated. |



<a name="github.spokes.blobs.v1.BlobsAPI-ListChangedBlobs"></a>

#### ListChangedBlobs

ListChangedBlobs returns the blobs oids (with the first tree path associated with it) reachable by a
commit excluding the blobs already reachable from other refs.

##### Dev URL

`http://127.0.0.1:8081/twirp/github.spokes.blobs.v1.BlobsAPI/ListChangedBlobs`

<a name="github.spokes.blobs.v1.ListChangedBlobsRequest"></a>

##### ListChangedBlobsRequest

ListChangedBlobsRequest includes the repository and the list of refs that have been updated.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| repository | [github.spokes.types.v1.Repository](../../types/v1/repository.md#github.spokes.types.v1.Repository) |  | repository is the repository to scope the blobs to. |
| cursor | [github.spokes.types.v1.Cursor](../../types/v1/cursor.md#github.spokes.types.v1.Cursor) |  |  |
| request_context | [github.spokes.types.v1.RequestContext](../../types/v1/request_context.md#github.spokes.types.v1.RequestContext) |  |  |
| (oneof selector) push_selector | [github.spokes.types.selectors.v1.PushSelector](../../types/selectors/v1/push_selector.md#github.spokes.types.selectors.v1.PushSelector) |  | push_selector is a push to select. Only use this in root repositories. |
| (oneof selector) fork_push_selector | [github.spokes.types.selectors.v1.ForkPushSelector](../../types/selectors/v1/fork_push_selector.md#github.spokes.types.selectors.v1.ForkPushSelector) |  | fork_push_selector is a push to select in a fork repository. |
| (oneof selector) universal_selector | [github.spokes.types.selectors.v1.UniversalSelector](../../types/selectors/v1/universal_selector.md#github.spokes.types.selectors.v1.UniversalSelector) |  | universal_selector selects all blobs in the repository that are reachable from any reference, including our hidden bookkeeping references. |
| (oneof selector) quarantine_objects_selector | [github.spokes.types.selectors.v1.QuarantineObjectsSelector](../../types/selectors/v1/quarantine_objects_selector.md#github.spokes.types.selectors.v1.QuarantineObjectsSelector) |  | quarantine_objects_selector selects blobs in a push, when its in quarantine. |
| commit_order | [ListChangedBlobsRequest.CommitOrder](#github.spokes.blobs.v1.ListChangedBlobsRequest.CommitOrder) |  | sets the commit order for graph traversal. |



<a name="github.spokes.blobs.v1.ListChangedBlobsResponse"></a>

##### ListChangedBlobsResponse

ListChangedBlobsResponse includes the blob with path and oid details


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| changed_blobs | [ChangedBlobItem](changed_blob_item.md#github.spokes.blobs.v1.ChangedBlobItem) | repeated | changed_blobs are the blobs that have changed for the request |
| next_cursor | [github.spokes.types.v1.Cursor](../../types/v1/cursor.md#github.spokes.types.v1.Cursor) |  |  |



<a name="github.spokes.blobs.v1.BlobsAPI-ListReachableBlobs"></a>

#### ListReachableBlobs

ListReachableBlobs returns a list of tree deltas within the scope of a ref update.
Delta entries include a tuple of path, commit oid, and blob oid information.

##### Dev URL

`http://127.0.0.1:8081/twirp/github.spokes.blobs.v1.BlobsAPI/ListReachableBlobs`

<a name="github.spokes.blobs.v1.ListReachableBlobsRequest"></a>

##### ListReachableBlobsRequest

ListReachableBlobsRequest returns a list of tree deltas within the scope of a ref update.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| repository | [github.spokes.types.v1.Repository](../../types/v1/repository.md#github.spokes.types.v1.Repository) |  | repository is the repository to scope the blobs to |
| cursor | [github.spokes.types.v1.Cursor](../../types/v1/cursor.md#github.spokes.types.v1.Cursor) |  |  |
| request_context | [github.spokes.types.v1.RequestContext](../../types/v1/request_context.md#github.spokes.types.v1.RequestContext) |  |  |
| (oneof selector) push_selector | [github.spokes.types.selectors.v1.PushSelector](../../types/selectors/v1/push_selector.md#github.spokes.types.selectors.v1.PushSelector) |  | push_selector is a push to select. Only use this in root repositories. |
| (oneof selector) fork_push_selector | [github.spokes.types.selectors.v1.ForkPushSelector](../../types/selectors/v1/fork_push_selector.md#github.spokes.types.selectors.v1.ForkPushSelector) |  | fork_push_selector is a push to select in a fork repository. |
| (oneof selector) universal_selector | [github.spokes.types.selectors.v1.UniversalSelector](../../types/selectors/v1/universal_selector.md#github.spokes.types.selectors.v1.UniversalSelector) |  | universal_selector selects all blobs in the repository that are reachable from any reference, including our hidden bookkeeping references. |
| (oneof selector) historical_push_selector | [github.spokes.types.selectors.v1.HistoricalPushSelector](../../types/selectors/v1/historical_push_selector.md#github.spokes.types.selectors.v1.HistoricalPushSelector) |  | historical_push_selector is a selector for selecting picking commits from past pushes based on (ref, before, after) tuples. |



<a name="github.spokes.blobs.v1.ListReachableBlobsResponse"></a>

##### ListReachableBlobsResponse

ListReachableBlobsResponse includes the blobs with blob oid, commit oid and path.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| reachable_blobs | [ReachableBlobItem](reachable_blob_item.md#github.spokes.blobs.v1.ReachableBlobItem) | repeated | reachable_blobs are the blobs that a reachable for the request. |
| next_cursor | [github.spokes.types.v1.Cursor](../../types/v1/cursor.md#github.spokes.types.v1.Cursor) |  |  |



<a name="github.spokes.blobs.v1.BlobsAPI-ListBlobOrigin"></a>

#### ListBlobOrigin

ListBlobOrigin searches through the repository and locates blobs matching the requested oids, and
returns the commit oid that the blob was introduced, and the first tree path encountered with that blob.

##### Dev URL

`http://127.0.0.1:8081/twirp/github.spokes.blobs.v1.BlobsAPI/ListBlobOrigin`

<a name="github.spokes.blobs.v1.ListBlobOriginRequest"></a>

##### ListBlobOriginRequest

ListBlobOriginRequest specifies the repository and a list of blob oids to return origin data for.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| repository | [github.spokes.types.v1.Repository](../../types/v1/repository.md#github.spokes.types.v1.Repository) |  | repository is the repository to scope the request to. |
| cursor | [github.spokes.types.v1.Cursor](../../types/v1/cursor.md#github.spokes.types.v1.Cursor) |  |  |
| request_context | [github.spokes.types.v1.RequestContext](../../types/v1/request_context.md#github.spokes.types.v1.RequestContext) |  |  |
| (oneof selector) object_id_selector | [github.spokes.types.selectors.v1.ObjectIDSelector](../../types/selectors/v1/object_id_selector.md#github.spokes.types.selectors.v1.ObjectIDSelector) |  | object_id_selector is a selector for picking individual blobs to fetch originating info for |
| (oneof ref_selector) push_selector | [github.spokes.types.selectors.v1.PushSelector](../../types/selectors/v1/push_selector.md#github.spokes.types.selectors.v1.PushSelector) |  | push_selector is a push to select. Only use this in root repositories. |
| (oneof ref_selector) fork_push_selector | [github.spokes.types.selectors.v1.ForkPushSelector](../../types/selectors/v1/fork_push_selector.md#github.spokes.types.selectors.v1.ForkPushSelector) |  | fork_push_selector is a push to select in a fork repository. |
| (oneof ref_selector) universal_selector | [github.spokes.types.selectors.v1.UniversalSelector](../../types/selectors/v1/universal_selector.md#github.spokes.types.selectors.v1.UniversalSelector) |  | universal_selector selects all blobs in the repository that are reachable from any reference, including our hidden bookkeeping references. |
| commit_order | [ListBlobOriginRequest.CommitOrder](#github.spokes.blobs.v1.ListBlobOriginRequest.CommitOrder) |  | sets the commit order for graph traversal. |
| max_commit_count | [uint32](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | max_commit_count is the maximum number of commits to read and send to diff-tree; defaults to 2500 max is also 2500 |



<a name="github.spokes.blobs.v1.ListBlobOriginResponse"></a>

##### ListBlobOriginResponse

ListBlobOriginResponse contains the individual blob origin items


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| blob_items | [BlobOriginItem](blob_origin_item.md#github.spokes.blobs.v1.BlobOriginItem) | repeated | Blob origin Items |
| next_cursor | [github.spokes.types.v1.Cursor](../../types/v1/cursor.md#github.spokes.types.v1.Cursor) |  |  |



<a name="github.spokes.blobs.v1.BlobsAPI-ListPushedBlobs"></a>

#### ListPushedBlobs

ListPushedBlobs returns a list of blobs reachable by a commit excluding the blobs reachable
from other refs.

##### Dev URL

`http://127.0.0.1:8081/twirp/github.spokes.blobs.v1.BlobsAPI/ListPushedBlobs`

<a name="github.spokes.blobs.v1.ListPushedBlobsRequest"></a>

##### ListPushedBlobsRequest

ListPushedBlobsRequest includes the repository and the list of refs that have been updated.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| repository | [github.spokes.types.v1.Repository](../../types/v1/repository.md#github.spokes.types.v1.Repository) |  | repository is the repository to scope the blobs to. |
| cursor | [github.spokes.types.v1.Cursor](../../types/v1/cursor.md#github.spokes.types.v1.Cursor) |  |  |
| request_context | [github.spokes.types.v1.RequestContext](../../types/v1/request_context.md#github.spokes.types.v1.RequestContext) |  |  |
| (oneof selector) push_selector | [github.spokes.types.selectors.v1.PushSelector](../../types/selectors/v1/push_selector.md#github.spokes.types.selectors.v1.PushSelector) |  | push_selector is a push to select. Only use this in root repositories. |
| (oneof selector) fork_push_selector | [github.spokes.types.selectors.v1.ForkPushSelector](../../types/selectors/v1/fork_push_selector.md#github.spokes.types.selectors.v1.ForkPushSelector) |  | fork_push_selector is a push to select in a fork repository. |



<a name="github.spokes.blobs.v1.ListPushedBlobsResponse"></a>

##### ListPushedBlobsResponse

ListPushedBlobsResponse contains a list of blobs with path, oid, and size details.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| pushed_blobs | [PushedBlobItem](pushed_blob_item.md#github.spokes.blobs.v1.PushedBlobItem) | repeated | pushed_blobs are the blobs that have been pushed for the request |
| next_cursor | [github.spokes.types.v1.Cursor](../../types/v1/cursor.md#github.spokes.types.v1.Cursor) |  |  |



<a name="github.spokes.blobs.v1.BlobsAPI-CountLines"></a>

#### CountLines

CountLines returns the amount of lines inside of the blobs requested
returns a list of either lines from the blob (determined by `\n`) or an error message.

##### Dev URL

`http://127.0.0.1:8081/twirp/github.spokes.blobs.v1.BlobsAPI/CountLines`

<a name="github.spokes.blobs.v1.CountLinesRequest"></a>

##### CountLinesRequest

CountLinesRequest includes the repository and the list of oids to count


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| request_context | [github.spokes.types.v1.RequestContext](../../types/v1/request_context.md#github.spokes.types.v1.RequestContext) |  |  |
| repository | [github.spokes.types.v1.Repository](../../types/v1/repository.md#github.spokes.types.v1.Repository) |  |  |
| (oneof selector) oid_selector | [github.spokes.types.selectors.v1.ObjectIDSelector](../../types/selectors/v1/object_id_selector.md#github.spokes.types.selectors.v1.ObjectIDSelector) |  |  |



<a name="github.spokes.blobs.v1.CountLinesResponse"></a>

##### CountLinesResponse

CountLinesResponse contains a list of the line count or an error


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| items | [CountLinesResponse.CountLinesItem](#github.spokes.blobs.v1.CountLinesResponse.CountLinesItem) | repeated |  |



<a name="github.spokes.blobs.v1.ListBlobOriginRequest.CommitOrder"></a>

### ListBlobOriginRequest.CommitOrder
CommitOrder encapsulates options for commit graph traversal.
These options tie to rev-list commit ordering options, see https://git-scm.com/docs/git-rev-list#Documentation/git-rev-list.txt

| Name | Number | Description |
| ---- | ------ | ----------- |
| COMMIT_ORDER_INVALID | 0 |  |
| COMMIT_ORDER_TOPO | 1 | topo order, ensures that no parent commit is traversed before its children have been traversed (default) |
| COMMIT_ORDER_REVERSE_CHRONOLOGICAL | 2 | reverse chronological order (rev-list default) |


<a name="github.spokes.blobs.v1.ListChangedBlobsRequest.CommitOrder"></a>

### ListChangedBlobsRequest.CommitOrder
CommitOrder encapsulates options for commit graph traversal.
These options tie to rev-list commit ordering options, see https://git-scm.com/docs/git-rev-list#Documentation/git-rev-list.txt

| Name | Number | Description |
| ---- | ------ | ----------- |
| COMMIT_ORDER_INVALID | 0 |  |
| COMMIT_ORDER_TOPO | 1 | topo order, ensures that no parent commit is traversed before its children have been traversed |
| COMMIT_ORDER_REVERSE_CHRONOLOGICAL | 2 | reverse chronological order (rev-list default) |


