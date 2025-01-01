[&lt;&lt; Spokes API](../../../README.md)

# spokes-api/trees/v1/trees_api.proto



## Services

<a name="github.spokes.trees.v1.TreesAPI"></a>

### TreesAPI

TreesAPI contains APIs for tree-related Git operations.

<a name="github.spokes.trees.v1.TreesAPI-ListTrees"></a>

#### ListTrees

ListTrees returns a list of tree entries associated with the tree.

##### Dev URL

`http://127.0.0.1:8081/twirp/github.spokes.trees.v1.TreesAPI/ListTrees`

<a name="github.spokes.trees.v1.ListTreesRequest"></a>

##### ListTreesRequest




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| repository | [github.spokes.types.v1.Repository](../../types/v1/repository.md#github.spokes.types.v1.Repository) |  | repository is the repository to scope the tree entries to. |
| cursor | [github.spokes.types.v1.Cursor](../../types/v1/cursor.md#github.spokes.types.v1.Cursor) |  |  |
| request_context | [github.spokes.types.v1.RequestContext](../../types/v1/request_context.md#github.spokes.types.v1.RequestContext) |  |  |
| (oneof selector) treeish_selector | [github.spokes.types.selectors.v1.TreeishSelector](../../types/selectors/v1/treeish_selector.md#github.spokes.types.selectors.v1.TreeishSelector) |  | treeish_selector is a selector for picking a tree by its treeish. |
| (oneof selector) treeish_and_path_selector | [github.spokes.types.selectors.v1.TreeishAndPathSelector](../../types/selectors/v1/treeish_and_path_selector.md#github.spokes.types.selectors.v1.TreeishAndPathSelector) |  | treeish_and_path_selector is a selector for picking a tree by its treeish and path. |
| recursive | [bool](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | recursive indicates whether the tree should be recursively traversed. |



<a name="github.spokes.trees.v1.ListTreesResponse"></a>

##### ListTreesResponse




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| entries | [github.spokes.types.v1.TreeEntry](../../types/v1/tree_entry.md#github.spokes.types.v1.TreeEntry) | repeated | entries contains the tree entries for the request. |
| next_cursor | [github.spokes.types.v1.Cursor](../../types/v1/cursor.md#github.spokes.types.v1.Cursor) |  |  |



<a name="github.spokes.trees.v1.TreesAPI-CompareTrees"></a>

#### CompareTrees

CompareTree returns a list of differences between two trees.

##### Dev URL

`http://127.0.0.1:8081/twirp/github.spokes.trees.v1.TreesAPI/CompareTrees`

<a name="github.spokes.trees.v1.CompareTreesRequest"></a>

##### CompareTreesRequest




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| repository | [github.spokes.types.v1.Repository](../../types/v1/repository.md#github.spokes.types.v1.Repository) |  | repository is the repository to scope the tree entries to. |
| cursor | [github.spokes.types.v1.Cursor](../../types/v1/cursor.md#github.spokes.types.v1.Cursor) |  | TODO document cursors |
| request_context | [github.spokes.types.v1.RequestContext](../../types/v1/request_context.md#github.spokes.types.v1.RequestContext) |  |  |
| (oneof selector) range_selector | [github.spokes.types.selectors.v1.RangeSelector](../../types/selectors/v1/range_selector.md#github.spokes.types.selectors.v1.RangeSelector) |  | range_selector is a selector for selecting a range of commits. |
| recursive | [bool](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | recursive indicates whether the tree should be recursively traversed. |
| include_renames | [bool](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | include_renames indicates whether the diff should try to figure out which blobs were renamed. |



<a name="github.spokes.trees.v1.CompareTreesResponse"></a>

##### CompareTreesResponse




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| entries | [github.spokes.types.v1.DiffEntry](../../types/v1/diff_entry.md#github.spokes.types.v1.DiffEntry) | repeated | entries contains the diff entries for the request. |
| next_cursor | [github.spokes.types.v1.Cursor](../../types/v1/cursor.md#github.spokes.types.v1.Cursor) |  |  |



<a name="github.spokes.trees.v1.TreesAPI-ReadTreeEntryOid"></a>

#### ReadTreeEntryOid

ReadTreeEntryOid returns the object id of a single entry in a tree, fetched by path.

##### Dev URL

`http://127.0.0.1:8081/twirp/github.spokes.trees.v1.TreesAPI/ReadTreeEntryOid`

<a name="github.spokes.trees.v1.ReadTreeEntryOidRequest"></a>

##### ReadTreeEntryOidRequest




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| repository | [github.spokes.types.v1.Repository](../../types/v1/repository.md#github.spokes.types.v1.Repository) |  | repository is the repository to scope the tree entry to. |
| request_context | [github.spokes.types.v1.RequestContext](../../types/v1/request_context.md#github.spokes.types.v1.RequestContext) |  | request_context contains additional information used by gitmon to determine which quotas to apply and how to enforce them |
| (oneof selector) treeish_selector | [github.spokes.types.selectors.v1.TreeishSelector](../../types/selectors/v1/treeish_selector.md#github.spokes.types.selectors.v1.TreeishSelector) |  | treeish_selector is a selector for picking a tree by its treeish. |
| path | [github.spokes.types.v1.Path](../../types/v1/path.md#github.spokes.types.v1.Path) |  | (Optional) path is the path to the tree entry If no path is specified, the root tree entry's oid is returned |
| type | [github.spokes.types.v1.ObjectType](../../types/v1/object_type.md#github.spokes.types.v1.ObjectType) |  | (Optional) type is the expected type of the git of object If the type is not matched, an exception is raised Defaults to returning any type |



<a name="github.spokes.trees.v1.ReadTreeEntryOidResponse"></a>

##### ReadTreeEntryOidResponse




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| oid | [github.spokes.types.v1.ObjectID](../../types/v1/object_id.md#github.spokes.types.v1.ObjectID) |  | oid is the object id of the tree entry |



