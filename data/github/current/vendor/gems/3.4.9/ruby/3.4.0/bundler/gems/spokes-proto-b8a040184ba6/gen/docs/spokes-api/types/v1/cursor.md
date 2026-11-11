[&lt;&lt; Spokes API](../../../README.md)

# spokes-api/types/v1/cursor.proto



## Types

<a name="github.spokes.types.v1.Cursor"></a>

### Cursor
Cursor represents an opaque value for obtaining more results.

APIs that support pagination include a 'cursor' field in responses and a 'next_cursor' field in requests. If there are no more results, cursor will be nil. If there are more results, it will be set. Clients should repeat the previous request and include the cursor in the request's 'next_cursor' field.

Here's an example of how you might loop through all the pages of results:

   request = buildRequest()
   loop {
     response = blobsAPI.listChangedBlobs(request)
     processResponse(response)
     if response.cursor == nil {
       break
     }
     request.next_cursor = response.cursor
   }


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| cursor | [bytes](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | <p>cursor is the opaque sequence of bytes indicating the next set of results. (required)</p> |





