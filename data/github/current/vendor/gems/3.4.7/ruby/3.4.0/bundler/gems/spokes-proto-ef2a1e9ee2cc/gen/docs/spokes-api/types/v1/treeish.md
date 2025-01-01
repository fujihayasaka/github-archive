[&lt;&lt; Spokes API](../../../README.md)

# spokes-api/types/v1/treeish.proto



## Types

<a name="github.spokes.types.v1.Treeish"></a>

### Treeish
Treeish represents the supported treeish representations of Spokes API.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| (oneof treeish) oid | [ObjectID](object_id.md#github.spokes.types.v1.ObjectID) |  | <p>oid is an object identifier.</p> |
| (oneof treeish) reference | [Reference](reference.md#github.spokes.types.v1.Reference) |  | <p>reference is a Git reference.</p> |
| (oneof treeish) revision | [Revision](revision.md#github.spokes.types.v1.Revision) |  | <p>revision is the Git revision</p> |





