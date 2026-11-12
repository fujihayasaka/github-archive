[&lt;&lt; Spokes API](../../../README.md)

# spokes-api/types/v2/attribution.proto



## Types

<a name="github.spokes.types.v2.Attribution"></a>

### Attribution
Attribution represents an individual and instant. Supports non-UTF-8 byte
values in the name and email fields.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| name | [bytes](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | <p>name is the name of the individual.</p> |
| email | [bytes](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | <p>email is the email address of the individual.</p> |
| date | [github.spokes.types.v1.Timestamp](../v1/timestamp.md#github.spokes.types.v1.Timestamp) |  | <p>date is the instant when the attribution (e.g. commit authorship) occurred.</p> |





