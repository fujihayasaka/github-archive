[&lt;&lt; Spokes API](../../../README.md)

# spokes-api/commits/v1/rev_list_filters.proto



## Types

<a name="github.spokes.commits.v1.RevListFilters"></a>

### RevListFilters



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| since | [github.spokes.types.v1.Timestamp](../../types/v1/timestamp.md#github.spokes.types.v1.Timestamp) |  | <p></p> |
| until | [github.spokes.types.v1.Timestamp](../../types/v1/timestamp.md#github.spokes.types.v1.Timestamp) |  | <p></p> |
| ignore_merges | [bool](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | <p></p> |
| authors | [github.spokes.types.v1.Pattern](../../types/v1/pattern.md#github.spokes.types.v1.Pattern) | repeated | <p></p> |
| committers | [github.spokes.types.v1.Pattern](../../types/v1/pattern.md#github.spokes.types.v1.Pattern) | repeated | <p></p> |
| pattern_options | [RevListFilters.PatternOptions](#github.spokes.commits.v1.RevListFilters.PatternOptions) |  | <p></p> |
| message_patterns | [github.spokes.types.v1.Pattern](../../types/v1/pattern.md#github.spokes.types.v1.Pattern) | repeated | <p></p> |
| pathspec | [github.spokes.types.v1.Pathspec](../../types/v1/pathspec.md#github.spokes.types.v1.Pathspec) |  | <p>pathspec can optionally be specified to only include commits which modify files matching at least one of the paths in the pathspec.</p> |





<a name="github.spokes.commits.v1.RevListFilters.PatternOptions"></a>

### RevListFilters.PatternOptions



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| mode | [RevListFilters.PatternOptions.Mode](#github.spokes.commits.v1.RevListFilters.PatternOptions.Mode) |  | <p></p> |
| ignore_case | [bool](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | <p></p> |





<a name="github.spokes.commits.v1.RevListFilters.PatternOptions.Mode"></a>

### RevListFilters.PatternOptions.Mode


| Name | Number | Description |
| ---- | ------ | ----------- |
| MODE_INVALID | 0 |  |
| MODE_BASIC_REGEXP | 1 | default |
| MODE_EXTENDED_REGEXP | 2 |  |
| MODE_FIXED_STRINGS | 3 | don’t interpret pattern as a regular expression |


