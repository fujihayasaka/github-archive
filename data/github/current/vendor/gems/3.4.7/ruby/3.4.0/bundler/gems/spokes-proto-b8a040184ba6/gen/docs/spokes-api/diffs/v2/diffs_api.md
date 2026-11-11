[&lt;&lt; Spokes API](../../../README.md)

# spokes-api/diffs/v2/diffs_api.proto



## Services

<a name="github.spokes.diffs.v2.DiffsAPI"></a>

### DiffsAPI

DiffsAPI contains APIs for diff-related Git operations.

<a name="github.spokes.diffs.v2.DiffsAPI-GetDiffPositions"></a>

#### GetDiffPositions

GetDiffPositions calculates the updated line numbers after applying a diff,
given the original line numbers. All line numbers are 1-indexed,
so the first line is represented by 1.

##### Dev URL

`http://127.0.0.1:8081/twirp/github.spokes.diffs.v2.DiffsAPI/GetDiffPositions`

<a name="github.spokes.diffs.v2.GetDiffPositionsRequest"></a>

##### GetDiffPositionsRequest




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| repository | [github.spokes.types.v1.Repository](../../types/v1/repository.md#github.spokes.types.v1.Repository) |  | The repository to operate on. |
| request_context | [github.spokes.types.v1.RequestContext](../../types/v1/request_context.md#github.spokes.types.v1.RequestContext) |  |  |
| source_oid | [github.spokes.types.selectors.v1.RepoObjectIDSelector](../../types/selectors/v1/repo_object_id_selector.md#github.spokes.types.selectors.v1.RepoObjectIDSelector) |  | The source treeish where the given file/line number is defined. Usually this is a commit object id, but it can be any treeish. |
| target_oid | [github.spokes.types.selectors.v1.RepoObjectIDSelector](../../types/selectors/v1/repo_object_id_selector.md#github.spokes.types.selectors.v1.RepoObjectIDSelector) |  | The target treeish in which we want to know the new line numbers. Usually this is a commit object id, but it can be any treeish. |
| source_items | [SourcePathLineNumbers](#github.spokes.diffs.v2.SourcePathLineNumbers) | repeated | Paths with line numbers that the caller wants the new line numbers for. A least 1 line number query within a path is required per request. A maximum of 1000 line number requests are allowed per request. |



<a name="github.spokes.diffs.v2.GetDiffPositionsResponse"></a>

##### GetDiffPositionsResponse




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| target_items | [TargetPathLineNumbers](#github.spokes.diffs.v2.TargetPathLineNumbers) | repeated | A mapping from source paths with line numbers to target paths with new line numbers in the given treeishs. |
| error | [string](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | The error message indicating the problem, if any. |



<a name="github.spokes.diffs.v2.DiffsAPI-ReadDiffSummary"></a>

#### ReadDiffSummary

ReadDiffSummary computes a summary of the changes between two commits and
a merge base.

##### Dev URL

`http://127.0.0.1:8081/twirp/github.spokes.diffs.v2.DiffsAPI/ReadDiffSummary`

<a name="github.spokes.diffs.v2.ReadDiffSummaryRequest"></a>

##### ReadDiffSummaryRequest

CheckCommitReachability checks whether the selected commits are reachable from a branch or tag.


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
| pathspec | [github.spokes.types.v1.Pathspec](../../types/v1/pathspec.md#github.spokes.types.v1.Pathspec) |  | pathspec can optionally be specified to limit the response to only files matching at least one of the paths in the pathspec. |



<a name="github.spokes.diffs.v2.ReadDiffSummaryResponse"></a>

##### ReadDiffSummaryResponse

ReadDiffSummaryResponse contains a summary of a diff.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| stat | [DiffSummaryStat](diff_summary_stat.md#github.spokes.diffs.v2.DiffSummaryStat) |  | stat is the total number of additions, deletions, and changed files in this diff. |
| deltas | [DiffSummaryDelta](diff_summary_delta.md#github.spokes.diffs.v2.DiffSummaryDelta) | repeated | deltas are the metadata about each modified file. |



<a name="github.spokes.diffs.v2.MappingState.StateCode"></a>

### MappingState.StateCode


| Name | Number | Description |
| ---- | ------ | ----------- |
| STATE_CODE_INVALID | 0 |  |
| STATE_CODE_SUCCESS | 1 |  |
| STATE_CODE_REMOVED_PATH | 2 |  |
| STATE_CODE_INVALID_PATH | 3 |  |
| STATE_CODE_CONTENT_TOO_LARGE | 4 |  |


