# ExpTasClient::AssignedVariant

## Properties

| Name | Type | Description | Notes |
| ---- | ---- | ----------- | ----- |
| **name** | **String** | Flight/variant name. |  |
| **numberline** | **String** | The experiment space this variant belongs to. |  |
| **is_forced** | **Boolean** | True if forced via requiredVariants. |  |
| **variant_allocation_id** | **Integer** | Allocation bucket ID. -1 for forced/default, 0+ for randomized. |  |

## Example

```ruby
require 'exp_tas_client'

instance = ExpTasClient::AssignedVariant.new(
  name: null,
  numberline: null,
  is_forced: null,
  variant_allocation_id: null
)
```

