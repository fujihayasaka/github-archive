[&lt;&lt; Spokes API](../../../README.md)

# spokes-api/types/selectors/v1/object_selector.proto



## Types

<a name="github.spokes.types.selectors.v1.ObjectSelector"></a>

### ObjectSelector
ObjectSelector is a selector for resolving objects.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| (oneof object) by_treeish_and_path | [ObjectSelector.TreeishAndPath](#github.spokes.types.selectors.v1.ObjectSelector.TreeishAndPath) |  | <p>e.g. main:proto/types/selectors/v1/object_selector.proto</p> |
| (oneof object) by_id | [github.spokes.types.v1.ObjectID](../../v1/object_id.md#github.spokes.types.v1.ObjectID) |  | <p>e.g. abb31df1fc098985b7a4576847e7d2bca719b8e4</p> |
| (oneof object) by_name | [github.spokes.types.v1.Revision](../../v1/revision.md#github.spokes.types.v1.Revision) |  | <p>e.g. main, refs/heads/master, abb31df1</p> |





<a name="github.spokes.types.selectors.v1.ObjectSelector.TreeishAndPath"></a>

### ObjectSelector.TreeishAndPath



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| treeish | [github.spokes.types.v1.Treeish](../../v1/treeish.md#github.spokes.types.v1.Treeish) |  | <p></p> |
| path | [github.spokes.types.v1.Path](../../v1/path.md#github.spokes.types.v1.Path) |  | <p></p> |





