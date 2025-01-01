[&lt;&lt; Spokes API](../../../README.md)

# spokes-api/diffs/v2/diff_delta.proto



## Types

<a name="github.spokes.diffs.v2.DiffDelta"></a>

### DiffDelta
DiffDelta is the information about each of the deltas in a diff, including
before and after state.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| old_tree_node | [github.spokes.types.v1.TreeEntry](../../types/v1/tree_entry.md#github.spokes.types.v1.TreeEntry) |  | <p>old_tree_node represents the state in the old file.</p> |
| new_tree_node | [github.spokes.types.v1.TreeEntry](../../types/v1/tree_entry.md#github.spokes.types.v1.TreeEntry) |  | <p>new_tree_node represents the state in the new file.</p> |
| diff_status | [github.spokes.types.v1.DiffStatus](../../types/v1/diff_status.md#github.spokes.types.v1.DiffStatus) |  | <p>diff_status represents whether the file was added, removed, copied, etc.</p> |
| (oneof _similarity) similarity | [uint32](https://developers.google.com/protocol-buffers/docs/proto3#scalar) | optional | <p>similarity represents the percentage of similarity. It is a value between 0 and 100 and applies only to renames.</p> |





