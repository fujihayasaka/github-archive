[&lt;&lt; Spokes API](../../../README.md)

# spokes-api/types/v1/token.proto



## Types

<a name="github.spokes.types.v1.Token"></a>

### Token
Token represents an opaque value for async operations.

APIs that operate asynchronously include a 'token' field in requests and responses.
A token will be returned in an initial response from a request with no token to allow polling for the status of the operation.
The value can be specified in subsequent requests to poll for the status of the operation.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| token | [bytes](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | <p>token is the opaque sequence of bytes to identify which async process to check. (required)</p> |





