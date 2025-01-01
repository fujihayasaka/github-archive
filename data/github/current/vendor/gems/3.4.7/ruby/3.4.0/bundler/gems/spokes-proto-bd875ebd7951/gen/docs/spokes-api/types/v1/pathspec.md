[&lt;&lt; Spokes API](../../../README.md)

# spokes-api/types/v1/pathspec.proto



## Types

<a name="github.spokes.types.v1.Pathspec"></a>

### Pathspec
Pathspec represents [Git pathspecs](https://git-scm.com/docs/gitglossary#Documentation/gitglossary.txt-aiddefpathspecapathspec)
to filter paths in a Git repository.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| items | [PathspecItem](#github.spokes.types.v1.PathspecItem) | repeated | <p></p> |





<a name="github.spokes.types.v1.PathspecItem"></a>

### PathspecItem



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| patterns | [Pattern](pattern.md#github.spokes.types.v1.Pattern) | repeated | <p></p> |
| pattern_type | [PathspecItem.PatternType](#github.spokes.types.v1.PathspecItem.PatternType) |  | <p></p> |
| ignore_case | [bool](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | <p></p> |
| exclude | [bool](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | <p></p> |





<a name="github.spokes.types.v1.PathspecItem.PatternType"></a>

### PathspecItem.PatternType


| Name | Number | Description |
| ---- | ------ | ----------- |
| PATTERN_TYPE_INVALID | 0 |  |
| PATTERN_TYPE_WILDCARD | 1 | Paths relative to the directory prefix will be matched against that pattern using fnmatch(3); in particular, * and ? can match directory separators. |
| PATTERN_TYPE_LITERAL | 2 | Wildcards in the pattern such as * or ? are treated as literal characters. |
| PATTERN_TYPE_GLOB | 3 | Git treats the pattern as a shell glob suitable for consumption by fnmatch(3) with the FNM_PATHNAME flag: wildcards in the pattern will not match a / in the pathname. |


