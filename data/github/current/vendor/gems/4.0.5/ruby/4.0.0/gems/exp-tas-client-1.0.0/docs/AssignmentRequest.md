# ExpTasClient::AssignmentRequest

## Properties

| Name | Type | Description | Notes |
| ---- | ---- | ----------- | ----- |
| **user_params** | **Hash&lt;String, String&gt;** | Key-value pairs for audience filtering and randomization. |  |
| **scopes** | **Array&lt;String&gt;** | Experiment subscription scopes to filter evaluation. | [optional] |
| **required_variants** | **Array&lt;String&gt;** | Variant names to force-assign. Duplicates are deduplicated. | [optional] |
| **blocked_variants** | **Array&lt;String&gt;** | Variant names to block from assignment. Duplicates are deduplicated. | [optional] |

## Example

```ruby
require 'exp_tas_client'

instance = ExpTasClient::AssignmentRequest.new(
  user_params: null,
  scopes: null,
  required_variants: null,
  blocked_variants: null
)
```

