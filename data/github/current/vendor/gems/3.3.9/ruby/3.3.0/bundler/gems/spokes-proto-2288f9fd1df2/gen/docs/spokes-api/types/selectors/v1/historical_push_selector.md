[&lt;&lt; Spokes API](../../../README.md)

# spokes-api/types/selectors/v1/historical_push_selector.proto



## Types

<a name="github.spokes.types.selectors.v1.HistoricalPushSelector"></a>

### HistoricalPushSelector
HistoricalPushSelector is a selector for selecting objects by that were included in a push that may have happened
some time ago. It does not distinct the commits included in the push and will consider commits that have since been
merged into other branches. For updates that create new references only the last commit will be selected.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| reference_updates | [github.spokes.types.v1.ReferenceUpdate](../../v1/reference_update.md#github.spokes.types.v1.ReferenceUpdate) | repeated | <p>reference_updates is the set of pushes to select.</p> |





