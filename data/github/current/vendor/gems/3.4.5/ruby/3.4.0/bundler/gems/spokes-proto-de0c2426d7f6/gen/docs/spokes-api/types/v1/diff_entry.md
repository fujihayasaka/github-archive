[&lt;&lt; Spokes API](../../../README.md)

# spokes-api/types/v1/diff_entry.proto



## Types

<a name="github.spokes.types.v1.DiffEntry"></a>

### DiffEntry
DiffEntry represents the diff of a blob between two trees.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| source_mode | [Mode](mode.md#github.spokes.types.v1.Mode) |  | <p>source_mode is the mode of the source blob. When status is STATUS_ADDITION, this will be nil.</p> |
| source_oid | [ObjectID](object_id.md#github.spokes.types.v1.ObjectID) |  | <p>source_oid is the object id of the source blob. When status is STATUS_ADDITION, this will be nil.</p> |
| source | [Path](path.md#github.spokes.types.v1.Path) |  | <p>source is the path of the source blob. When status is STATUS_ADDITION, this will be nil.</p> |
| destination_mode | [Mode](mode.md#github.spokes.types.v1.Mode) |  | <p>destination_mode is the mode of the destination blob. When status is STATUS_DELETION, this will be nil.</p> |
| destination_oid | [ObjectID](object_id.md#github.spokes.types.v1.ObjectID) |  | <p>destination_oid is the object id of the destination blob. When status is STATUS_DELETION, this will be nil.</p> |
| destination | [Path](path.md#github.spokes.types.v1.Path) |  | <p>destination is the path of the destination blob. When status is STATUS_DELETION, this will be nil.</p> |
| status | [DiffEntry.Status](#github.spokes.types.v1.DiffEntry.Status) |  | <p>status is the status of the blob in the diff.</p> |
| score | [uint32](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | <p>score is the similarity of the blobs for certain statuses. This will only be filled in when status is STATUS_COPY or STATUS_RENAME. In all other cases it will be 0.</p> |





<a name="github.spokes.types.v1.DiffEntry.Status"></a>

### DiffEntry.Status
Status encapsulates the possible statuses a blob can have in a diff.

| Name | Number | Description |
| ---- | ------ | ----------- |
| STATUS_INVALID | 0 |  |
| STATUS_ADDITION | 1 | STATUS_ADDITION indicates that a file was added. Only the destination fields will be present. |
| STATUS_COPY | 2 | STATUS_COPY indicates that a file was copied. The source fields will be the original file and the destination fields will be the new file. The score field will be filled in with Git's confidence that this was a copy and not an addition. |
| STATUS_DELETION | 3 | STATUS_DELETION indicates that a file was deleted. Only the source fields will be present. |
| STATUS_MODIFICATION | 4 | STATUS_MODIFICATION indicates that a file was modified, either contents or mode. The source and destination fields will all be filled in. The source path and destination path will be the same. |
| STATUS_RENAME | 5 | STATUS_RENAME indicates that a file was renamed. The source and destination fields will be filled in. The source field will be filled in with Git's confidence that this was a rename and not a deletion and addition. |
| STATUS_TYPE | 6 | STATUS_TYPE indicates that a file's type changed. The source and destination fields will all be filled in. The source path and destination path will be the same. |
| STATUS_UNMERGED | 7 | STATUS_UNMERGED indicates that a file in the index is not merged. This will never be returned by Spokes API. |
| STATUS_UNKNOWN | 8 | STATUS_UNKNOWN indicates that a change's type is not known. This is most probably a bug. Please report it! |


