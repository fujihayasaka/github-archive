[&lt;&lt; Spokes API](../../../README.md)

# spokes-api/types/v1/commit.proto



## Types

<a name="github.spokes.types.v1.Commit"></a>

### Commit
Commit represents a Git commit.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| tree | [ObjectID](object_id.md#github.spokes.types.v1.ObjectID) |  | <p>tree is the tree identifier associated with the commit.</p> |
| parents | [ObjectID](object_id.md#github.spokes.types.v1.ObjectID) | repeated | <p>parents is the list of commits that parent the current one.</p> |
| author | [Attribution](attribution.md#github.spokes.types.v1.Attribution) |  | <p>author is who authored the commit along with a timestamp.</p> |
| committer | [Attribution](attribution.md#github.spokes.types.v1.Attribution) |  | <p>author is who committed the commit along with a timestamp.</p> |
| gpg_signature | [string](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | <p>gpg_signature is the GPG signature for the commit.</p> |
| message | [bytes](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | <p>message contains the commit message and description as raw bytes.</p> |





