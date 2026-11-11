[&lt;&lt; Spokes API](../../../README.md)

# spokes-api/types/v1/attribute.proto



## Types

<a name="github.spokes.types.v1.Attribute"></a>

### Attribute
Attribute represents an attribute.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| key | [bytes](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | <p>key is the key of the attribute.</p> |
| (oneof value) byte_value | [bytes](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | <p>A value has been assigned to the attribute.</p> |
| (oneof value) bool_value | [bool](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | <p>The attribute is set or unset (i.e. true or false)</p> |





