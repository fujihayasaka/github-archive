[&lt;&lt; Spokes API](../../../README.md)

# spokes-api/tags/v1/tags_api.proto



## Services

<a name="github.spokes.tags.v1.TagsAPI"></a>

### TagsAPI

TagsAPI contains APIs for Git operations involving tag objects.

<a name="github.spokes.tags.v1.TagsAPI-CreateTag"></a>

#### CreateTag

CreateTag creates a tag object from the given tag metadata and returns
the object ID.

##### Dev URL

`http://127.0.0.1:8081/twirp/github.spokes.tags.v1.TagsAPI/CreateTag`

<a name="github.spokes.tags.v1.CreateTagRequest"></a>

##### CreateTagRequest




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| repository | [github.spokes.types.v1.Repository](../../types/v1/repository.md#github.spokes.types.v1.Repository) |  | repository is the repository into which we're writing the new tag. |
| request_context | [github.spokes.types.v1.RequestContext](../../types/v1/request_context.md#github.spokes.types.v1.RequestContext) |  |  |
| name | [bytes](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | name is the name of the tag to be stored in the object's metadata. |
| target | [github.spokes.types.v1.ObjectID](../../types/v1/object_id.md#github.spokes.types.v1.ObjectID) |  | target is the object ID of the object to be tagged. |
| tagger | [github.spokes.types.v2.Attribution](../../types/v2/attribution.md#github.spokes.types.v2.Attribution) |  | tagger is the attribution associated with this tag. |
| message | [bytes](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | message is the tag's message. |



<a name="github.spokes.tags.v1.CreateTagResponse"></a>

##### CreateTagResponse




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| transaction_context | [github.spokes.types.v1.TransactionContext](../../types/v1/transaction_context.md#github.spokes.types.v1.TransactionContext) |  | transaction_context contains the updated state after performing the write. |
| oid | [github.spokes.types.v1.ObjectID](../../types/v1/object_id.md#github.spokes.types.v1.ObjectID) |  | oid is the object ID of the newly-created tag |



