[&lt;&lt; Spokes API](../../../README.md)

# spokes-api/types/selectors/v1/range_selector.proto



## Types

<a name="github.spokes.types.selectors.v1.RangeSelector"></a>

### RangeSelector
RangeSelector is a selector for selecting a range of objects by their treeish.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| start | [github.spokes.types.v1.Treeish](../../v1/treeish.md#github.spokes.types.v1.Treeish) |  | <p>start is the starting treeish of the range.</p> |
| end | [github.spokes.types.v1.Treeish](../../v1/treeish.md#github.spokes.types.v1.Treeish) |  | <p>end is the ending treeish of the range.</p> |
| paths | [github.spokes.types.v1.Path](../../v1/path.md#github.spokes.types.v1.Path) | repeated | <p>paths is the list of paths which the diff output should be limited to.</p> |





