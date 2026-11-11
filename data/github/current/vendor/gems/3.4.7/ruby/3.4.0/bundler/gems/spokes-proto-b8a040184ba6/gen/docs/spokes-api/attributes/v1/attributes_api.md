[&lt;&lt; Spokes API](../../../README.md)

# spokes-api/attributes/v1/attributes_api.proto



## Services

<a name="github.spokes.attributes.v1.AttributesAPI"></a>

### AttributesAPI

AttributesAPI contains APIs for attribute-related Git operations.

<a name="github.spokes.attributes.v1.AttributesAPI-ReadAttributes"></a>

#### ReadAttributes

ReadAttributes returns a list of attributes for the specified paths in a
treeish.

##### Dev URL

`http://127.0.0.1:8081/twirp/github.spokes.attributes.v1.AttributesAPI/ReadAttributes`

<a name="github.spokes.attributes.v1.ReadAttributesRequest"></a>

##### ReadAttributesRequest




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| repository | [github.spokes.types.v1.Repository](../../types/v1/repository.md#github.spokes.types.v1.Repository) |  | repository is the repository to scope the attributes to. |
| request_context | [github.spokes.types.v1.RequestContext](../../types/v1/request_context.md#github.spokes.types.v1.RequestContext) |  |  |
| (oneof selector) treeish_selector | [github.spokes.types.selectors.v1.TreeishSelector](../../types/selectors/v1/treeish_selector.md#github.spokes.types.selectors.v1.TreeishSelector) |  | treeish_selector selects a tree by its treeish. |
| paths | [github.spokes.types.v1.Path](../../types/v1/path.md#github.spokes.types.v1.Path) | repeated | paths is the list of paths to read the attributes from. A maximum of 1000 paths can be read per request. |
| (oneof keys_selector) universal_selector | [github.spokes.types.selectors.v1.UniversalSelector](../../types/selectors/v1/universal_selector.md#github.spokes.types.selectors.v1.UniversalSelector) |  | universal_selector selects all attributes for the treeish and path. |
| (oneof keys_selector) key_selector | [github.spokes.types.selectors.v1.KeySelector](../../types/selectors/v1/key_selector.md#github.spokes.types.selectors.v1.KeySelector) |  | key_selector selects individual attributes by their keys for the treeish and path. |



<a name="github.spokes.attributes.v1.ReadAttributesResponse"></a>

##### ReadAttributesResponse




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| attribute_items | [AttributeItem](attribute_item.md#github.spokes.attributes.v1.AttributeItem) | repeated | attribute_items is the list of attributes for each path in the treeish. |



