[&lt;&lt; Spokes API](../../../README.md)

# spokes-api/references/v1/reference_item.proto



## Types

<a name="github.spokes.references.v1.RefListOptions"></a>

### RefListOptions
This message is used to add filtering options to endpoints that list references.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| points_at | [github.spokes.types.v1.ObjectID](../../types/v1/object_id.md#github.spokes.types.v1.ObjectID) | repeated | <p>Points at is the object ID that the references should point at.</p> |
| contains | [github.spokes.types.v1.ObjectID](../../types/v1/object_id.md#github.spokes.types.v1.ObjectID) | repeated | <p>Contains is the object ID that the references should contain.</p> |





<a name="github.spokes.references.v1.ReferenceItem"></a>

### ReferenceItem
ReferenceItem is a reference's name and object details.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| reference | [github.spokes.types.v1.Reference](../../types/v1/reference.md#github.spokes.types.v1.Reference) |  | <p>reference is the name of the reference.</p> |
| object | [github.spokes.types.v1.Object](../../types/v1/object.md#github.spokes.types.v1.Object) |  | <p>object represents the object being referred to.</p> |





