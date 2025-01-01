[&lt;&lt; Spokes API](../../../README.md)

# spokes-api/references/v1/ref_with_commit_time.proto



## Types

<a name="github.spokes.references.v1.RefWithCommitTime"></a>

### RefWithCommitTime
RefWithCommitTime contains the name of a reference plus OID information with a
timestamp


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| reference | [github.spokes.types.v1.Reference](../../types/v1/reference.md#github.spokes.types.v1.Reference) |  | <p>reference is the Git reference.</p> |
| target_id | [github.spokes.types.v1.ObjectID](../../types/v1/object_id.md#github.spokes.types.v1.ObjectID) |  | <p>target_id is the reference OID.</p> |
| peeled_id | [github.spokes.types.v1.ObjectID](../../types/v1/object_id.md#github.spokes.types.v1.ObjectID) |  | <p>peeled_id is the peeled OID. For tags this is the tag OID for annotated tags or the OID of the commit the tag points to for lightweight tags.</p> |
| commit_time | [github.spokes.types.v1.Timestamp](../../types/v1/timestamp.md#github.spokes.types.v1.Timestamp) |  | <p>commit_time is the timestamp of the tag or commit target of the reference.</p> |





