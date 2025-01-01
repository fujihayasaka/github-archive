[&lt;&lt; Spokes API](../../../README.md)

# spokes-api/types/v1/sockstat_kv.proto



## Types

<a name="github.spokes.types.v1.SockstatKV"></a>

### SockstatKV
SockstatKV represents one item of sockstat data.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| key | [string](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | <p>key represents the key for this item.</p> |
| (oneof value) bytes_value | [bytes](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | <p></p> |
| (oneof value) int64_value | [int64](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | <p></p> |
| (oneof value) bool_value | [bool](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | <p></p> |
| (oneof value) uint64_value | [uint64](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | <p></p> |





