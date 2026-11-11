[&lt;&lt; Spokes API](../../../README.md)

# spokes-api/submodules/v1/submodules_api.proto



## Services

<a name="github.spokes.submodules.v1.SubmodulesAPI"></a>

### SubmodulesAPI

SubmodulesAPI contains APIs for submodule-related Git operations.

<a name="github.spokes.submodules.v1.SubmodulesAPI-ReadSubmodules"></a>

#### ReadSubmodules

ReadSubmodule returns the submodule object for a given repository and path.

##### Dev URL

`http://127.0.0.1:8081/twirp/github.spokes.submodules.v1.SubmodulesAPI/ReadSubmodules`

<a name="github.spokes.submodules.v1.ReadSubmodulesRequest"></a>

##### ReadSubmodulesRequest




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| repository | [github.spokes.types.v1.Repository](../../types/v1/repository.md#github.spokes.types.v1.Repository) |  | repository is the repository to scope the submodule lookup to. |
| request_context | [github.spokes.types.v1.RequestContext](../../types/v1/request_context.md#github.spokes.types.v1.RequestContext) |  |  |
| (oneof selector) treeish_selector | [github.spokes.types.selectors.v1.TreeishSelector](../../types/selectors/v1/treeish_selector.md#github.spokes.types.selectors.v1.TreeishSelector) |  | treeish_selector is a selector for picking a tree by its treeish. |
| paths | [github.spokes.types.v1.Path](../../types/v1/path.md#github.spokes.types.v1.Path) | repeated | paths is the list of submodule paths to read the details. There is a limit of 1000 paths. |



<a name="github.spokes.submodules.v1.ReadSubmodulesResponse"></a>

##### ReadSubmodulesResponse




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| submodules | [github.spokes.types.v1.Submodule](../../types/v1/submodule.md#github.spokes.types.v1.Submodule) | repeated | submodules is the list of submodules. |



