[&lt;&lt; Spokes API](../../../README.md)

# spokes-api/diffs/v2/diffs_api.proto



## Services

<a name="github.spokes.diffs.v2.DiffsAPI"></a>

### DiffsAPI

DiffsAPI contains APIs for diff-related Git operations.

<a name="github.spokes.diffs.v2.DiffsAPI-ReadDiffSummary"></a>

#### ReadDiffSummary

ReadDiffSummary computes a summary of the changes between two commits and
a merge base.

##### Dev URL

`http://127.0.0.1:8081/twirp/github.spokes.diffs.v2.DiffsAPI/ReadDiffSummary`

<a name="github.spokes.diffs.v2.ReadDiffSummaryRequest"></a>

##### ReadDiffSummaryRequest

CheckCommitReachability checks whether the selected commits are reachablle from a branch or tag.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| repository | [github.spokes.types.v1.Repository](../../types/v1/repository.md#github.spokes.types.v1.Repository) |  | repository is the repository to operate on. |
| request_context | [github.spokes.types.v1.RequestContext](../../types/v1/request_context.md#github.spokes.types.v1.RequestContext) |  |  |
| (oneof oid1) object_id1 | [github.spokes.types.v1.ObjectID](../../types/v1/object_id.md#github.spokes.types.v1.ObjectID) |  |  |
| (oneof oid1) repo_object_id1 | [github.spokes.types.selectors.v1.RepoObjectIDSelector](../../types/selectors/v1/repo_object_id_selector.md#github.spokes.types.selectors.v1.RepoObjectIDSelector) |  |  |
| (oneof oid1) root_selector1 | [github.spokes.types.selectors.v1.RootSelector](../../types/selectors/v1/root_selector.md#github.spokes.types.selectors.v1.RootSelector) |  |  |
| (oneof oid2) object_id2 | [github.spokes.types.v1.ObjectID](../../types/v1/object_id.md#github.spokes.types.v1.ObjectID) |  |  |
| (oneof oid2) repo_object_id2 | [github.spokes.types.selectors.v1.RepoObjectIDSelector](../../types/selectors/v1/repo_object_id_selector.md#github.spokes.types.selectors.v1.RepoObjectIDSelector) |  |  |
| (oneof base_oid) base_object_id | [github.spokes.types.v1.ObjectID](../../types/v1/object_id.md#github.spokes.types.v1.ObjectID) |  |  |
| (oneof base_oid) repo_base_object_id | [github.spokes.types.selectors.v1.RepoObjectIDSelector](../../types/selectors/v1/repo_object_id_selector.md#github.spokes.types.selectors.v1.RepoObjectIDSelector) |  |  |
| (oneof base_oid) none_base | [github.spokes.types.selectors.v1.NoneSelector](../../types/selectors/v1/none_selector.md#github.spokes.types.selectors.v1.NoneSelector) |  |  |
| diff_algorithm | [github.spokes.types.v1.DiffAlgorithm](../../types/v1/diff_algorithm.md#github.spokes.types.v1.DiffAlgorithm) |  | diff_algorithm is the diff algorithm to be used. |
| ignore_whitespace | [bool](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | ignore_whitespace indicates whether whitespace is to be ignored. |
| include_stat | [bool](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | include_stat indicates whether to include stat information (additions, deletions, and changed files), both for individual files and for the diff as a whole, in the output. |



<a name="github.spokes.diffs.v2.ReadDiffSummaryResponse"></a>

##### ReadDiffSummaryResponse

ReadDiffSummaryResponse contains a summary of a diff.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| stat | [DiffSummaryStat](diff_summary_stat.md#github.spokes.diffs.v2.DiffSummaryStat) |  | stat is the total number of additions, deletions, and changed files in this diff. |
| deltas | [DiffSummaryDelta](diff_summary_delta.md#github.spokes.diffs.v2.DiffSummaryDelta) | repeated | deltas are the metadata about each modified file. |



