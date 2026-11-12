# ExpTasClient::AssignmentResponse

## Properties

| Name | Type | Description | Notes |
| ---- | ---- | ----------- | ----- |
| **feature_variables** | **Hash&lt;String, String&gt;** | Feature flag key-value pairs from assigned variants. |  |
| **assigned_variants** | [**Array&lt;AssignedVariant&gt;**](AssignedVariant.md) | Non-default variants the user was assigned to. |  |
| **data_version** | **Integer** | Version of the experimentation config used. |  |
| **assignment_context** | **String** | Semicolon-separated non-default assignments for telemetry. |  |

## Example

```ruby
require 'exp_tas_client'

instance = ExpTasClient::AssignmentResponse.new(
  feature_variables: null,
  assigned_variants: null,
  data_version: null,
  assignment_context: null
)
```

