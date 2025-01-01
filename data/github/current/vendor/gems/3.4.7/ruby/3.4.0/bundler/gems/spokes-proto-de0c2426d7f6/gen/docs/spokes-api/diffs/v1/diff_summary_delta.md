[&lt;&lt; Spokes API](../../../README.md)

# spokes-api/diffs/v1/diff_summary_delta.proto



## Types

<a name="github.spokes.diffs.v1.DiffSummaryDelta"></a>

### DiffSummaryDelta
DiffSummaryDelta is the information about each of the deltas in a diff
summary, including before and after state and number of additions and
deletions.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| delta | [DiffDelta](diff_delta.md#github.spokes.diffs.v1.DiffDelta) |  | <p></p> |
| (oneof changes) binary_changes | [DiffSummaryBinaryChanges](diff_summary_binary_changes.md#github.spokes.diffs.v1.DiffSummaryBinaryChanges) |  | <p></p> |
| (oneof changes) text_changes | [DiffSummaryTextChanges](diff_summary_text_changes.md#github.spokes.diffs.v1.DiffSummaryTextChanges) |  | <p></p> |





