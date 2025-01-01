[&lt;&lt; Spokes API](../../../README.md)

# spokes-api/types/selectors/v1/merge_object_selector.proto



## Types

<a name="github.spokes.types.selectors.v1.MergeObjectSelector"></a>

### MergeObjectSelector
MergeObjectSelector is a selector for one of the source entities of a merge
operation (i.e., left/right/base). The selector does not allow specifying
objects using a dynamic identifier (e.g. a reference) to ensure consistent
results across replicas.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| (oneof object) by_oid | [github.spokes.types.v1.ObjectID](../../v1/object_id.md#github.spokes.types.v1.ObjectID) |  | <p>by_oid is the object ID of a mergeable entity, e.g. abb31df1fc098985b7a4576847e7d2bca719b8e4</p> |
| source_repository | [github.spokes.types.v1.Repository](../../v1/repository.md#github.spokes.types.v1.Repository) |  | <p>source_repository is the source repository containing the entity. If unspecified, the source repository is inherited from the request.</p> |





