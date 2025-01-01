[&lt;&lt; Spokes API](../../../README.md)

# spokes-api/types/selectors/v1/fork_push_selector.proto



## Types

<a name="github.spokes.types.selectors.v1.ForkPushSelector"></a>

### ForkPushSelector
ForkPushSelector is a selector for objects that were included in a push to a fork.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| base_repository | [github.spokes.types.v1.Repository](../../v1/repository.md#github.spokes.types.v1.Repository) |  | <p>base_repository is the parent of this repository.</p> |
| reference_updates | [github.spokes.types.v1.ReferenceUpdate](../../v1/reference_update.md#github.spokes.types.v1.ReferenceUpdate) | repeated | <p>reference_updates is the set of pushes to select.</p> |





