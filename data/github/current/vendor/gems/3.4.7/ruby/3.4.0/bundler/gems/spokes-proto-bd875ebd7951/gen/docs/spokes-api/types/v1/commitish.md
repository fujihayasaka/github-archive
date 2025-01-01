[&lt;&lt; Spokes API](../../../README.md)

# spokes-api/types/v1/commitish.proto



## Types

<a name="github.spokes.types.v1.Commitish"></a>

### Commitish
Commitish represents the supported commitish representations of Spokes API.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| (oneof commitish) oid | [ObjectID](object_id.md#github.spokes.types.v1.ObjectID) |  | <p>oid is an object identifier.</p> |
| (oneof commitish) reference | [Reference](reference.md#github.spokes.types.v1.Reference) |  | <p>reference is a Git reference.</p> |
| (oneof commitish) revision | [Revision](revision.md#github.spokes.types.v1.Revision) |  | <p>revision is the Git revision</p> |





