[&lt;&lt; Spokes API](../../../README.md)

# spokes-api/streaming/v1/blob_filter.proto



## Types

<a name="github.spokes.batch.v1.BlobFilter"></a>

### BlobFilter
Filters to apply to blob content as part of responding to a
BatchBlobsRequest. Only blobs that meet these criteria will be returned.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| plain_text_only | [bool](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | <p>Only return plain text blobs.</p> |
| utf8_only | [bool](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | <p>Only return blobs that are utf8 encoded.</p> |
| max_line_length | [int64](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | <p>Only return blobs where all lines are less than this value (set to zero to disable).</p> |
| min_size | [int64](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | <p>Only return blobs that are larger than min size.</p> |
| max_size | [int64](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | <p>Only return blobs that are less than max size (set to zero to disable).</p> |
| truncate_at | [uint32](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | <p>If set, truncate all returned blobs after this number of bytes.</p> |





