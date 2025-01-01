[&lt;&lt; Spokes API](../../../README.md)

# spokes-api/merges/v1/merges_api.proto



## Services

<a name="github.spokes.merges.v1.MergesAPI"></a>

### MergesAPI

MergesAPI contains APIs for merge-related Git operations.

<a name="github.spokes.merges.v1.MergesAPI-FindMergeBases"></a>

#### FindMergeBases

FindMergeBases computes one or all of the merge bases between two commits
using a specified algorithm.

##### Dev URL

`http://127.0.0.1:8081/twirp/github.spokes.merges.v1.MergesAPI/FindMergeBases`

<a name="github.spokes.merges.v1.FindMergeBasesRequest"></a>

##### FindMergeBasesRequest




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| repository | [github.spokes.types.v1.Repository](../../types/v1/repository.md#github.spokes.types.v1.Repository) |  | repository is the repository to operate on. |
| request_context | [github.spokes.types.v1.RequestContext](../../types/v1/request_context.md#github.spokes.types.v1.RequestContext) |  |  |
| base_oid | [github.spokes.types.v1.ObjectID](../../types/v1/object_id.md#github.spokes.types.v1.ObjectID) |  | base_oid is the base object ID to operate on. |
| head_oid | [github.spokes.types.v1.ObjectID](../../types/v1/object_id.md#github.spokes.types.v1.ObjectID) |  | head_oid is the head object ID to operate on. |
| merge_base_type | [MergeBaseType](merge_base_type.md#github.spokes.merges.v1.MergeBaseType) |  | merge_base_type is the type of merge base computation to perform. |



<a name="github.spokes.merges.v1.FindMergeBasesResponse"></a>

##### FindMergeBasesResponse




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| bases | [github.spokes.types.v1.ObjectID](../../types/v1/object_id.md#github.spokes.types.v1.ObjectID) | repeated | bases are the resultant bases. |



