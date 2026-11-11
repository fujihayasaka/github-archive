[&lt;&lt; Spokes API](../../../README.md)

# spokes-api/experimental/experimental_api.proto



## Services

<a name="github.spokes.experimental.v1.ExperimentalAPI"></a>

### ExperimentalAPI

ExperimentalAPI defines experimental APIs that we want to iterate on
quickly. These APIs are likely to change in backwards-incompatible ways.

<a name="github.spokes.experimental.v1.ExperimentalAPI-ResolveObjects"></a>

#### ResolveObjects

ResolveObjects performs object resolutions for all
the provided
repositories in the request and returns multiple resolved objects. The
entries in the response are in the same order as the items in the request.

##### Dev URL

`http://127.0.0.1:8081/twirp/github.spokes.experimental.v1.ExperimentalAPI/ResolveObjects`

<a name="github.spokes.experimental.v1.ResolveObjectsRequest"></a>

##### ResolveObjectsRequest




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| object_selectors_by_repo | [ObjectSelectorsByRepo](#github.spokes.experimental.v1.ObjectSelectorsByRepo) | repeated | List of objects to resolve grouped by repo |
| request_context | [github.spokes.types.v1.RequestContext](../types/v1/request_context.md#github.spokes.types.v1.RequestContext) |  |  |



<a name="github.spokes.experimental.v1.ResolveObjectsResponse"></a>

##### ResolveObjectsResponse




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| resolved_batches | [ResolvedItemsByRepo](#github.spokes.experimental.v1.ResolvedItemsByRepo) | repeated | List of resolved items grouped by repository |



