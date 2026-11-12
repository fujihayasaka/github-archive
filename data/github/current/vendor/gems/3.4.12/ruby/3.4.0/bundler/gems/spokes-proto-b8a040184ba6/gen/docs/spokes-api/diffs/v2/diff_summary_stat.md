[&lt;&lt; Spokes API](../../../README.md)

# spokes-api/diffs/v2/diff_summary_stat.proto



## Types

<a name="github.spokes.diffs.v2.DiffSummaryStat"></a>

### DiffSummaryStat
DiffSummaryStat represents the changes for a text file.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| additions | [uint64](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | <p>additions is the number of lines added (including modified lines).</p> |
| deletions | [uint64](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | <p>deletions is the number of lines deleted (including modified lines).</p> |
| changed_files | [uint32](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | <p>changed_files is the number of changed files.</p> |





