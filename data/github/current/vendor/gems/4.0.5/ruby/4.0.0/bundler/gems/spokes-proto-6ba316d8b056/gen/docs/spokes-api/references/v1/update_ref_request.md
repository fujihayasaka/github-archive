[&lt;&lt; Spokes API](../../../README.md)

# spokes-api/references/v1/update_ref_request.proto



## Types

<a name="github.spokes.references.v1.UpdateRefRequest"></a>

### UpdateRefRequest
UpdateRefRequest represents a request to update or verify a ref.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| fast_forward | [UpdateRefRequest.FastForward](#github.spokes.references.v1.UpdateRefRequest.FastForward) |  | <p>fast_forward indicates the fast forward status of the ref.</p> |
| reference | [github.spokes.types.v1.Reference](../../types/v1/reference.md#github.spokes.types.v1.Reference) |  | <p>reference is the ref involved in the update.</p> |
| (oneof operation) ref_verify | [UpdateRefOpVerify](update_ref_op_verify.md#github.spokes.references.v1.UpdateRefOpVerify) |  | <p></p> |
| (oneof operation) ref_verify_update | [UpdateRefOpVerifyUpdate](update_ref_op_verify_update.md#github.spokes.references.v1.UpdateRefOpVerifyUpdate) |  | <p></p> |
| (oneof operation) ref_update | [UpdateRefOpUpdate](update_ref_op_update.md#github.spokes.references.v1.UpdateRefOpUpdate) |  | <p></p> |





<a name="github.spokes.references.v1.UpdateRefRequest.FastForward"></a>

### UpdateRefRequest.FastForward
FastForward reflects whether we should record that the update was a
fast forward.

| Name | Number | Description |
| ---- | ------ | ----------- |
| FAST_FORWARD_INVALID | 0 |  |
| FAST_FORWARD_OMIT | 1 | Don't record whether the update was a fast-forward. |
| FAST_FORWARD_COMPUTE | 2 | Compute whether the update was a fast-forward and record that. |
| FAST_FORWARD_TRUE | 3 | Assert that the update is or is not a fast-forward and record that value. |
| FAST_FORWARD_FALSE | 4 |  |


