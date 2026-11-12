[&lt;&lt; Spokes API](../../../README.md)

# spokes-api/merges/v1/merge_conflict.proto



## Types

<a name="github.spokes.merges.v1.MergeConflict"></a>

### MergeConflict
MergeConflict represents the conflicts for an individual path in a merge. A
`nil` TreeEntry value indicates that the entry is not present in the
associated tree.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| base | [MergeConflict.TreeEntry](#github.spokes.merges.v1.MergeConflict.TreeEntry) |  | <p>base is the conflicted tree entry in the base.</p> |
| head | [MergeConflict.TreeEntry](#github.spokes.merges.v1.MergeConflict.TreeEntry) |  | <p>head is the conflicted tree entry in the head.</p> |
| merge_base | [MergeConflict.TreeEntry](#github.spokes.merges.v1.MergeConflict.TreeEntry) |  | <p>merge_base is the conflicted tree entry in the merge base.</p> |





<a name="github.spokes.merges.v1.MergeConflict.TreeEntry"></a>

### MergeConflict.TreeEntry
TreeEntry represents a tree entry (in a conflict or resolution) for a
merge operation.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| mode | [github.spokes.types.v1.Mode](../../types/v1/mode.md#github.spokes.types.v1.Mode) |  | <p>mode is the file mode of the entry.</p> |
| oid | [github.spokes.types.v1.ObjectID](../../types/v1/object_id.md#github.spokes.types.v1.ObjectID) |  | <p>oid is the object ID of the entry.</p> |
| path | [github.spokes.types.v1.Path](../../types/v1/path.md#github.spokes.types.v1.Path) |  | <p>path is the path to the entry in its tree.</p> |





