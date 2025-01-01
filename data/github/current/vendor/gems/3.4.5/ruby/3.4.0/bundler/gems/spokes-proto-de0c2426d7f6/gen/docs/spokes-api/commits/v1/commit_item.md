[&lt;&lt; Spokes API](../../../README.md)

# spokes-api/commits/v1/commit_item.proto



## Types

<a name="github.spokes.commits.v1.CommitItem"></a>

### CommitItem
CommitItem is a commit's OID and content.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| oid | [github.spokes.types.v1.ObjectID](../../types/v1/object_id.md#github.spokes.types.v1.ObjectID) |  | <p>oid represents the commit's object id.</p> |
| (oneof commit_item_content) commit_content | [github.spokes.types.v1.Commit](../../types/v1/commit.md#github.spokes.types.v1.Commit) |  | <p>commit is the data contained in the commit.</p> |
| (oneof commit_item_content) error | [string](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | <p>the error when we are unable to parse the commit</p> |





