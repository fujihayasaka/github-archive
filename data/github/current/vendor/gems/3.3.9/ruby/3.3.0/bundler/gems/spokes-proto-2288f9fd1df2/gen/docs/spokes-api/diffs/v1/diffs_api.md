[&lt;&lt; Spokes API](../../../README.md)

# spokes-api/diffs/v1/diffs_api.proto



## Services

<a name="github.spokes.diffs.v1.DiffsAPI"></a>

### DiffsAPI

DiffsAPI contains APIs for diff-related Git operations.

<a name="github.spokes.diffs.v1.DiffsAPI-ReadDiffSummary"></a>

#### ReadDiffSummary

ReadDiffSummary computes a summary of the changes between two commits and
a merge base.

##### Dev URL

`http://127.0.0.1:8081/twirp/github.spokes.diffs.v1.DiffsAPI/ReadDiffSummary`

<a name="github.spokes.diffs.v1.ReadDiffSummaryRequest"></a>

##### ReadDiffSummaryRequest

CheckCommitReachability checks whether the selected commits are reachablle from a branch or tag.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| repository | [github.spokes.types.v1.Repository](../../types/v1/repository.md#github.spokes.types.v1.Repository) |  | repository is the repository to operate on. |
| request_context | [github.spokes.types.v1.RequestContext](../../types/v1/request_context.md#github.spokes.types.v1.RequestContext) |  |  |
| (oneof oid1) object_id1 | [github.spokes.types.v1.ObjectID](../../types/v1/object_id.md#github.spokes.types.v1.ObjectID) |  |  |
| (oneof oid1) root_selector1 | [github.spokes.types.selectors.v1.RootSelector](../../types/selectors/v1/root_selector.md#github.spokes.types.selectors.v1.RootSelector) |  |  |
| oid2 | [github.spokes.types.v1.ObjectID](../../types/v1/object_id.md#github.spokes.types.v1.ObjectID) |  | oid2 is the second head to operate on. Diff information will be between the computed merge base and this commit. |
| base_oid | [github.spokes.types.v1.ObjectID](../../types/v1/object_id.md#github.spokes.types.v1.ObjectID) |  | base_selector is the merge base to use; if it is not provided, one will be computed. |
| diff_algorithm | [github.spokes.types.v1.DiffAlgorithm](../../types/v1/diff_algorithm.md#github.spokes.types.v1.DiffAlgorithm) |  | diff_algorithm is the diff algorithm to be used. |
| ignore_whitespace | [bool](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | ignore_whitespace indicates whether whitespace is to be ignored. |
| include_stat | [bool](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | include_stat indicates whether to include stat information (additions, deletions, and changed files), both for individual files and for the diff as a whole, in the output. |



<a name="github.spokes.diffs.v1.ReadDiffSummaryResponse"></a>

##### ReadDiffSummaryResponse

ReadDiffSummaryResponse contains a summary of a diff.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| stat | [DiffSummaryStat](diff_summary_stat.md#github.spokes.diffs.v1.DiffSummaryStat) |  | stat is the total number of additions, deletions, and changed files in this diff. |
| deltas | [DiffSummaryDelta](diff_summary_delta.md#github.spokes.diffs.v1.DiffSummaryDelta) | repeated | deltas are the metadata about each modified file. |



