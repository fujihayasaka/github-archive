[&lt;&lt; Spokes API](../../../README.md)

# spokes-api/merges/v1/merge_base_type.proto



## Types

<a name="github.spokes.merges.v1.MergeBaseType"></a>

### MergeBaseType
MergeBaseType encapsulates the possible algorithms for computing merge
bases.

| Name | Number | Description |
| ---- | ------ | ----------- |
| MERGE_BASE_TYPE_INVALID | 0 | MERGE_BASE_TYPE_INVALID indicates an invalid merge base type. |
| MERGE_BASE_TYPE_SINGLE | 1 | MERGE_BASE_TYPE_SINGLE indicates a request for a single merge base using the default algorithm. |
| MERGE_BASE_TYPE_ALL | 2 | MERGE_BASE_TYPE_ALL indicates a request for all of the merge bases. |
| MERGE_BASE_TYPE_BEST | 3 | MERGE_BASE_TYPE_BEST indicates a request for a single merge base using our best merge base algorithm. |


