[&lt;&lt; Spokes API](../../../README.md)

# spokes-api/types/selectors/v1/prefix_selector.proto



## Types

<a name="github.spokes.types.selectors.v1.PrefixSelector"></a>

### PrefixSelector
PrefixSelector is a selector for selecting based on a prefix matcher.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| include | [github.spokes.types.v1.Prefix](../../v1/prefix.md#github.spokes.types.v1.Prefix) | repeated | <p>include are the prefixes to match against.</p> |
| exclude | [github.spokes.types.v1.Prefix](../../v1/prefix.md#github.spokes.types.v1.Prefix) | repeated | <p>exclude are the prefixes that, if matched, indicate a reference should be excluded from the result.</p> |





