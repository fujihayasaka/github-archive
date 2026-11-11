# exp-tas-client

Ruby client for the EXP Treatment Assignment Service.

This client is automatically generated from the [OpenAPI spec](../../docs/api/schema.yaml) using [OpenAPI Generator](https://openapi-generator.tech).

## Installation

Add this to your Gemfile:

```ruby
gem "exp-tas-client", git: "https://github.com/github/exp-tas", glob: "client-ruby/*.gemspec"
```

## Usage

```ruby
require "exp_tas_client"

config = ExpTasClient::Configuration.new
config.scheme = "http"
config.host = "localhost:18080"
config.base_path = "/api/v1"

client = ExpTasClient::ApiClient.new(config)
api = ExpTasClient::DefaultApi.new(client)

request = ExpTasClient::AssignmentRequest.new(
  user_params: { "user_id" => "my-user", "clientid" => "my-app" }
)

begin
  result = api.get_treatment_assignment(request)
  puts result.feature_variables
  puts result.assigned_variants.map(&:name)
rescue ExpTasClient::ApiError => e
  puts "Request failed (#{e.code}): #{e.message}"
end
```

## API

| Method | HTTP | Description |
|--------|------|-------------|
| `DefaultApi#get_treatment_assignment` | `POST /treatment-assignment` | Get treatment assignments |

## Models

- `AssignmentRequest` — request with `user_params`, optional `scopes`, `required_variants`, `blocked_variants`
- `AssignmentResponse` — response with `feature_variables`, `assigned_variants`, `data_version`, `assignment_context`
- `AssignedVariant` — variant with `name`, `numberline`, `is_forced`, `variant_allocation_id`
- `ErrorResponse` — error with `message`

## Regenerating

```bash
make gen-ruby
```

Requires Docker.
