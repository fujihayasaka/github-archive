[&lt;&lt; Spokes API](../../../README.md)

# spokes-api/types/selectors/v1/resolved_base_selector.proto



## Types

<a name="github.spokes.types.selectors.v1.ResolvedBaseSelector"></a>

### ResolvedBaseSelector
ResolvedBaseSelector is a selector that triggers internal resolution of a merge base.
This will cause the system to internally call ResolveBaseOID to compute the merge base
for the given OIDs before proceeding with the operation.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| (oneof oid1) object_id1 | [github.spokes.types.v1.ObjectID](../../v1/object_id.md#github.spokes.types.v1.ObjectID) |  | <p></p> |
| (oneof oid1) repo_object_id1 | [RepoObjectIDSelector](repo_object_id_selector.md#github.spokes.types.selectors.v1.RepoObjectIDSelector) |  | <p></p> |
| (oneof oid1) root_selector1 | [RootSelector](root_selector.md#github.spokes.types.selectors.v1.RootSelector) |  | <p></p> |
| (oneof oid2) object_id2 | [github.spokes.types.v1.ObjectID](../../v1/object_id.md#github.spokes.types.v1.ObjectID) |  | <p></p> |
| (oneof oid2) repo_object_id2 | [RepoObjectIDSelector](repo_object_id_selector.md#github.spokes.types.selectors.v1.RepoObjectIDSelector) |  | <p></p> |
| (oneof base_oid) base_object_id | [github.spokes.types.v1.ObjectID](../../v1/object_id.md#github.spokes.types.v1.ObjectID) |  | <p></p> |
| (oneof base_oid) repo_base_object_id | [RepoObjectIDSelector](repo_object_id_selector.md#github.spokes.types.selectors.v1.RepoObjectIDSelector) |  | <p></p> |
| (oneof base_oid) none_base | [NoneSelector](none_selector.md#github.spokes.types.selectors.v1.NoneSelector) |  | <p></p> |





