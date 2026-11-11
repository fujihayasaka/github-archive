[&lt;&lt; Spokes API](../../../README.md)

# spokes-api/types/v1/reference_update.proto



## Types

<a name="github.spokes.types.v1.ReferenceUpdate"></a>

### ReferenceUpdate
ReferenceUpdate represents a push or other change to a single ref.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| reference | [Reference](reference.md#github.spokes.types.v1.Reference) |  | <p>reference is the ref involved in the update. (required)</p> |
| before | [ObjectID](object_id.md#github.spokes.types.v1.ObjectID) |  | <p>before is the oid that was the tip of the ref before the update. In case of a new ref being added, this field should be left empty.</p> |
| after | [ObjectID](object_id.md#github.spokes.types.v1.ObjectID) |  | <p>after is the oid that is the tip of the ref after the update. In case of a ref being deleted, this field should be left empty.</p> |





