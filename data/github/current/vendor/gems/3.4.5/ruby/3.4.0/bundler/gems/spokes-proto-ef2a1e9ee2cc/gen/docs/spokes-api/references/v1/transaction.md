[&lt;&lt; Spokes API](../../../README.md)

# spokes-api/references/v1/transaction.proto



## Types

<a name="github.spokes.references.v1.Transaction"></a>

### Transaction
Transaction represents a transaction to update or verify one or more refs.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| committer_name | [bytes](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | <p>committer_name is the name of the committer. By convention, this is a personal name.</p> |
| committer_email | [bytes](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | <p>committer_email is the email of the committer.</p> |
| committer_time | [string](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | <p>committer_time is the time of the commit. It may be any string suitable for Git.</p> |
| reflog_msg | [string](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | <p>reflog_msg is the message for the reflog.</p> |
| ref_update | [UpdateRefRequest](update_ref_request.md#github.spokes.references.v1.UpdateRefRequest) | repeated | <p>ref_update indicates the ref updates to perform.</p> |





