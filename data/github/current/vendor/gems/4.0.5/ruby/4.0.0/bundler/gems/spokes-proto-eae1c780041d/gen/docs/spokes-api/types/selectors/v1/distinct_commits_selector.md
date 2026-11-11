[&lt;&lt; Spokes API](../../../README.md)

# spokes-api/types/selectors/v1/distinct_commits_selector.proto



## Types

<a name="github.spokes.types.selectors.v1.DistinctCommitsSelector"></a>

### DistinctCommitsSelector
DistinctCommitsSelector is a selector for locating commits that are
unique to the target branch in a repository.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| reference | [github.spokes.types.v1.Reference](../../v1/reference.md#github.spokes.types.v1.Reference) |  | <p></p> |
| oid | [github.spokes.types.v1.ObjectID](../../v1/object_id.md#github.spokes.types.v1.ObjectID) |  | <p>The point in the ref's history to start the search from. If omitted, the head of the reference will be used.</p> |
| exclude_oids | [github.spokes.types.v1.ObjectID](../../v1/object_id.md#github.spokes.types.v1.ObjectID) | repeated | <p>A maximum of 10 OIDs can be excluded from the results.</p> |





