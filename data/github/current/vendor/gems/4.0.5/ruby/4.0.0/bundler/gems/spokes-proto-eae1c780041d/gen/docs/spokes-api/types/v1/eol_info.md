[&lt;&lt; Spokes API](../../../README.md)

# spokes-api/types/v1/eol_info.proto



## Types

<a name="github.spokes.types.v1.EolInfo"></a>

### EolInfo
EolInfo describes the end-of-line style detected in a blob's content.
These values correspond to git's %(eolinfo:blob) output.

| Name | Number | Description |
| ---- | ------ | ----------- |
| EOL_INFO_INVALID | 0 | EOL_INFO_INVALID is present because enums require a zero value. This should never be used. |
| EOL_INFO_UNSET | 1 | EOL_INFO_UNSET indicates that eol info is not available for this entry. |
| EOL_INFO_UNSUPPORTED | 2 | EOL_INFO_UNSUPPORTED indicates the entry is not a regular file (e.g. a directory or submodule) and eol detection does not apply. Corresponds to git's bare "b/" eolinfo output. |
| EOL_INFO_LF | 3 | EOL_INFO_LF indicates the blob uses Unix-style line endings (LF). |
| EOL_INFO_CRLF | 4 | EOL_INFO_CRLF indicates the blob uses Windows-style line endings (CRLF). |
| EOL_INFO_MIXED | 5 | EOL_INFO_MIXED indicates the blob uses a mix of line endings. |
| EOL_INFO_NONE | 6 | EOL_INFO_NONE indicates the blob has no line endings (e.g. a single-line file). |
| EOL_INFO_BINARY | 7 | EOL_INFO_BINARY indicates the blob is binary (not a text file). |


