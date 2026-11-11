[&lt;&lt; Spokes API](../../../README.md)

# spokes-api/types/v1/diff_status.proto



## Types

<a name="github.spokes.types.v1.DiffStatus"></a>

### DiffStatus
Status encapsulates the possible statuses a blob can have in a diff.

| Name | Number | Description |
| ---- | ------ | ----------- |
| DIFF_STATUS_INVALID | 0 |  |
| DIFF_STATUS_ADDITION | 1 | DIFF_STATUS_ADDITION indicates that a file was added. Only the destination fields will be present. |
| DIFF_STATUS_COPY | 2 | DIFF_STATUS_COPY indicates that a file was copied. The source fields will be the original file and the destination fields will be the new file. The score field will be filled in with Git's confidence that this was a copy and not an addition. |
| DIFF_STATUS_DELETION | 3 | DIFF_STATUS_DELETION indicates that a file was deleted. Only the source fields will be present. |
| DIFF_STATUS_MODIFICATION | 4 | DIFF_STATUS_MODIFICATION indicates that a file was modified, either contents or mode. The source and destination fields will all be filled in. The source path and destination path will be the same. |
| DIFF_STATUS_RENAME | 5 | DIFF_STATUS_RENAME indicates that a file was renamed. The source and destination fields will be filled in. The source field will be filled in with Git's confidence that this was a rename and not a deletion and addition. |
| DIFF_STATUS_TYPE | 6 | DIFF_STATUS_TYPE indicates that a file's type changed. The source and destination fields will all be filled in. The source path and destination path will be the same. |
| DIFF_STATUS_UNMERGED | 7 | DIFF_STATUS_UNMERGED indicates that a file in the index is not merged. This will never be returned by Spokes API. |
| DIFF_STATUS_UNKNOWN | 8 | DIFF_STATUS_UNKNOWN indicates that a change's type is not known. This is most probably a bug. Please report it! |


