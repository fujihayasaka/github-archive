[&lt;&lt; Spokes API](../../../README.md)

# spokes-api/types/v1/object.proto



## Types

<a name="github.spokes.types.v1.Object"></a>

### Object
Object represents a Git object id and type.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| type | [Object.Type](#github.spokes.types.v1.Object.Type) |  | <p>type indicates the object type.</p> |
| oid | [ObjectID](object_id.md#github.spokes.types.v1.ObjectID) |  | <p>oid represents the object id.</p> |
| size | [uint64](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | <p>size represents the full size of the object.</p> |
| mode | [uint32](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | <p>mode represents the file mode of the object. Only applicable to objects that are resolved as tree entries.</p> |





<a name="github.spokes.types.v1.Object.Type"></a>

### Object.Type
values correspond with those found in git/object.c.

| Name | Number | Description |
| ---- | ------ | ----------- |
| TYPE_INVALID | 0 |  |
| TYPE_COMMIT | 1 |  |
| TYPE_TREE | 2 |  |
| TYPE_BLOB | 3 |  |
| TYPE_TAG | 4 |  |


