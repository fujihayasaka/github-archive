[&lt;&lt; Spokes API](../../../README.md)

# spokes-api/types/selectors/v1/ref_glob_selector.proto



## Types

<a name="github.spokes.types.selectors.v1.RefGlobSelector"></a>

### RefGlobSelector
RefGlobSelector is a selector for selecting refs matching a glob.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| include | [github.spokes.types.v1.Glob](../../v1/glob.md#github.spokes.types.v1.Glob) | repeated | <p>include are the globs to match against.</p> |
| exclude | [github.spokes.types.v1.Glob](../../v1/glob.md#github.spokes.types.v1.Glob) | repeated | <p>exclude are globs that, if matched, indicate a reference should be excluded from the result.</p> |
| ignore_case | [bool](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | <p>ignore_case controls whether matching is done case-sensitively.</p> |





