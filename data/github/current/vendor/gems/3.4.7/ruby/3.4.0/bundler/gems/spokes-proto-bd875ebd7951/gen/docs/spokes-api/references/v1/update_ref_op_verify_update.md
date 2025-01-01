[&lt;&lt; Spokes API](../../../README.md)

# spokes-api/references/v1/update_ref_op_verify_update.proto



## Types

<a name="github.spokes.references.v1.UpdateRefOpVerifyUpdate"></a>

### UpdateRefOpVerifyUpdate
UpdateRefOpVerifyUpdate represents an update to a single ref verifying the
prior value


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| before | [github.spokes.types.v1.ObjectID](../../types/v1/object_id.md#github.spokes.types.v1.ObjectID) |  | <p>before is the expected ref at the tip of the reference</p> |
| after | [github.spokes.types.v1.ObjectID](../../types/v1/object_id.md#github.spokes.types.v1.ObjectID) |  | <p>after is the value to set to reference</p> |





