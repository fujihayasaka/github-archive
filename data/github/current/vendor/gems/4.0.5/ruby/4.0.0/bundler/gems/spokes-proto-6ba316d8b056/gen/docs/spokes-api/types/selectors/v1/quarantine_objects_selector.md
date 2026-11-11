[&lt;&lt; Spokes API](../../../README.md)

# spokes-api/types/selectors/v1/quarantine_objects_selector.proto



## Types

<a name="github.spokes.types.selectors.v1.QuarantineObjectsSelector"></a>

### QuarantineObjectsSelector
QuarantineObjectsSelector is a selector for selecting objects by that were included in a push
specifically while they are still in quarantine.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| filter_preexisting_objects | [bool](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | <p>filter_preexisting_objects indicates whether to include objects that were already present in the repository before the push. By default this is false, meaning that objects in the quarantine and in the main repository will be included.</p> |





