[&lt;&lt; Spokes API](../../../README.md)

# spokes-api/types/v1/mode.proto



## Types

<a name="github.spokes.types.v1.Mode"></a>

### Mode
Mode represents the mode of the blob, the possible modes are:
- 100644 for a regular file,
- 100755 for an executable file,
- 040000 for a directory,
- 120000 for a symlink,
- 160000 for a submodule.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| mode | [uint32](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | <p>mode is the blob mode, encoded as an integer in octal.</p> |





