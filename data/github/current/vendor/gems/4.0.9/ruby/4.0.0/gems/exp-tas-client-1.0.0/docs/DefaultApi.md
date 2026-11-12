# ExpTasClient::DefaultApi

All URIs are relative to */api/v1*

| Method | HTTP request | Description |
| ------ | ------------ | ----------- |
| [**get_treatment_assignment**](DefaultApi.md#get_treatment_assignment) | **POST** /treatment-assignment | Get treatment assignments |


## get_treatment_assignment

> <AssignmentResponse> get_treatment_assignment(assignment_request)

Get treatment assignments

### Examples

```ruby
require 'time'
require 'exp_tas_client'

api_instance = ExpTasClient::DefaultApi.new
assignment_request = ExpTasClient::AssignmentRequest.new({user_params: { key: 'inner_example'}}) # AssignmentRequest | 

begin
  # Get treatment assignments
  result = api_instance.get_treatment_assignment(assignment_request)
  p result
rescue ExpTasClient::ApiError => e
  puts "Error when calling DefaultApi->get_treatment_assignment: #{e}"
end
```

#### Using the get_treatment_assignment_with_http_info variant

This returns an Array which contains the response data, status code and headers.

> <Array(<AssignmentResponse>, Integer, Hash)> get_treatment_assignment_with_http_info(assignment_request)

```ruby
begin
  # Get treatment assignments
  data, status_code, headers = api_instance.get_treatment_assignment_with_http_info(assignment_request)
  p status_code # => 2xx
  p headers # => { ... }
  p data # => <AssignmentResponse>
rescue ExpTasClient::ApiError => e
  puts "Error when calling DefaultApi->get_treatment_assignment_with_http_info: #{e}"
end
```

### Parameters

| Name | Type | Description | Notes |
| ---- | ---- | ----------- | ----- |
| **assignment_request** | [**AssignmentRequest**](AssignmentRequest.md) |  |  |

### Return type

[**AssignmentResponse**](AssignmentResponse.md)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

