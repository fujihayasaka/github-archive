[&lt;&lt; Spokes API](../../../README.md)

# spokes-api/commits/v1/cleanup_mode.proto



## Types

<a name="github.spokes.commits.v1.CleanupMode"></a>

### CleanupMode
CleanupMode defines how to clean up the commit message.

| Name | Number | Description |
| ---- | ------ | ----------- |
| CLEANUP_MODE_INVALID | 0 | CLEANUP_MODE_INVALID is the default enum value and should not be used. |
| CLEANUP_MODE_WHITESPACE | 1 | CLEANUP_MODE_WHITESPACE strips leading and trailing empty lines, trailing whitespace, and collapses consecutive empty lines. |
| CLEANUP_MODE_VERBATIM | 2 | CLEANUP_MODE_VERBATIM does not modify the commit message. |


