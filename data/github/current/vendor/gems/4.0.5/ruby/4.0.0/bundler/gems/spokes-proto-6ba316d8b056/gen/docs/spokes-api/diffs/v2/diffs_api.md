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



<a name="github.spokes.diffs.v2.DiffsAPI-ReadDiffPairs"></a>

#### ReadDiffPairs

ReadDiffPairs computes the diffs between pairs of files.

##### Dev URL

`http://127.0.0.1:8081/twirp/github.spokes.diffs.v2.DiffsAPI/ReadDiffPairs`

<a name="github.spokes.diffs.v2.ReadDiffPairsRequest"></a>

##### ReadDiffPairsRequest




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| repository | [github.spokes.types.v1.Repository](../../types/v1/repository.md#github.spokes.types.v1.Repository) |  | repository is the repository to operate on. |
| request_context | [github.spokes.types.v1.RequestContext](../../types/v1/request_context.md#github.spokes.types.v1.RequestContext) |  |  |
| cursor | [github.spokes.types.v1.Cursor](../../types/v1/cursor.md#github.spokes.types.v1.Cursor) |  | cursor is used for paging the results of the diff pair computation. When provided, the response will continue from where the previous request left off via the next_cursor in the previous response. |
| (oneof pairs) diff_deltas | [DiffDeltaSelector](#github.spokes.diffs.v2.DiffDeltaSelector) |  |  |
| resolved_base_selector | [github.spokes.types.selectors.v1.ResolvedBaseSelector](../../types/selectors/v1/resolved_base_selector.md#github.spokes.types.selectors.v1.ResolvedBaseSelector) |  | (Optional) resolved_base_selector is the selector that triggers internal resolution of a merge base |
| options | [ReadDiffPairsOptions](#github.spokes.diffs.v2.ReadDiffPairsOptions) |  | (Optional) contains options to customize the diff output. |



<a name="github.spokes.diffs.v2.ReadDiffPairsResponse"></a>

##### ReadDiffPairsResponse




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| items | [DiffPairResult](#github.spokes.diffs.v2.DiffPairResult) | repeated | items are the per-file diff results, aligned with the requested pairs. |
| next_cursor | [github.spokes.types.v1.Cursor](../../types/v1/cursor.md#github.spokes.types.v1.Cursor) |  |  |



<a name="github.spokes.diffs.v2.DiffsAPI-GetDiffAppliable"></a>

#### GetDiffAppliable

GetDiffAppliable checks whether a given diff patch can be applied to a commit via `git apply --3way`.
If the patch does not contain index lines, git falls back to applying without 3-way merge.

##### Dev URL

`http://127.0.0.1:8081/twirp/github.spokes.diffs.v2.DiffsAPI/GetDiffAppliable`

<a name="github.spokes.diffs.v2.GetDiffAppliableRequest"></a>

##### GetDiffAppliableRequest

GetDiffAppliableRequest checks whether a diff patch can be applied to a commit.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| repository | [github.spokes.types.v1.Repository](../../types/v1/repository.md#github.spokes.types.v1.Repository) |  | repository is the repository to operate on. |
| request_context | [github.spokes.types.v1.RequestContext](../../types/v1/request_context.md#github.spokes.types.v1.RequestContext) |  | request_context is extra information used for quotas and request handling. |
| commit_oid | [github.spokes.types.v1.ObjectID](../../types/v1/object_id.md#github.spokes.types.v1.ObjectID) |  | commit_oid is the commit SHA to check the patch against. |
| diff_patch | [bytes](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | diff_patch is the unified diff patch content to check for appliability. |



<a name="github.spokes.diffs.v2.GetDiffAppliableResponse"></a>

##### GetDiffAppliableResponse

GetDiffAppliableResponse contains the result of the appliability check.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| result | [DiffAppliableResult](diff_appliable_result.md#github.spokes.diffs.v2.DiffAppliableResult) |  | result indicates whether and why the patch can or cannot be applied. |
| resolved_diff_patch | [bytes](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | resolved_diff_patch is the result of applying the input diff_patch to the commit, expressed as a new diff. Only populated when it differs from the input diff_patch. |



<a name="github.spokes.diffs.v2.DiffsAPI-CreateCommitFromDiff"></a>

#### CreateCommitFromDiff

CreateCommitFromDiff applies a diff to the given treeish creating an object.

##### Dev URL

`http://127.0.0.1:8081/twirp/github.spokes.diffs.v2.DiffsAPI/CreateCommitFromDiff`

<a name="github.spokes.diffs.v2.CreateCommitFromDiffRequest"></a>

##### CreateCommitFromDiffRequest




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| repository | [github.spokes.types.v1.Repository](../../types/v1/repository.md#github.spokes.types.v1.Repository) |  | repository is the repository to operate on. |
| request_context | [github.spokes.types.v1.RequestContext](../../types/v1/request_context.md#github.spokes.types.v1.RequestContext) |  |  |
| diff_patch | [bytes](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | diff_patch is the unified diff patch content for creating the commit object |
| base_oid | [github.spokes.types.v1.ObjectID](../../types/v1/object_id.md#github.spokes.types.v1.ObjectID) |  | base_oid is the required base object ID to operate on |
| author | [github.spokes.types.v2.Attribution](../../types/v2/attribution.md#github.spokes.types.v2.Attribution) |  | author is the author of the commit |
| committer | [github.spokes.types.v2.Attribution](../../types/v2/attribution.md#github.spokes.types.v2.Attribution) |  | committer is the committer of the commit |
| message | [bytes](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | message is the commit message |



<a name="github.spokes.diffs.v2.CreateCommitFromDiffResponse"></a>

##### CreateCommitFromDiffResponse




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| transaction_context | [github.spokes.types.v1.TransactionContext](../../types/v1/transaction_context.md#github.spokes.types.v1.TransactionContext) |  | transaction_context is the updated state after creating the objects. |
| oid | [github.spokes.types.v1.ObjectID](../../types/v1/object_id.md#github.spokes.types.v1.ObjectID) |  | oid is the object id of the created commit |



<a name="github.spokes.diffs.v2.MappingState.StateCode"></a>

### MappingState.StateCode


| Name | Number | Description |
| ---- | ------ | ----------- |
| STATE_CODE_INVALID | 0 |  |
| STATE_CODE_SUCCESS | 1 |  |
| STATE_CODE_REMOVED_PATH | 2 |  |
| STATE_CODE_INVALID_PATH | 3 |  |
| STATE_CODE_CONTENT_TOO_LARGE | 4 |  |
| STATE_CODE_RENAME_TOO_COMPLEX | 5 |  |


