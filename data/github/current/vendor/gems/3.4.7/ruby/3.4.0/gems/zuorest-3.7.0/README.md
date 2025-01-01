# Zuorest

This is a lightweight wrapper around the Zuora REST API.

## Installation

### As a Ruby Gem

Add this line to your application's Gemfile:

```ruby
gem 'zuorest'
```

## Features

- Lightweight wrapper for Zuora REST API
- OAuth token management with customizable storage
- Configurable timeouts and retries
- Support for multiple API categories (accounts, orders, subscriptions, etc.)

For the complete Zuora API documentation, see the [Zuora Docs](https://www.zuora.com/developer/api-reference).

## Usage

### Basic Setup

```ruby
Zuorest::Model::Base.zuora_rest_client = Zuorest::RestClient.new(
  server_url: "https://rest.apisandbox.zuora.com",
  access_key_id: "ZUORA_ACCESS_KEY",
  secret_access_key: "ZUORA_SECRET_ACCESS_KEY",
  client_id: "ZUORA_CLIENT_ID",
  client_secret: "ZUORA_CLIENT_SECRET"
)

# Example: Find an order
order = Zuorest::Model::Order.find "O-00000021"
```

### Rest Client

The Rest Client can be used to make HTTP requests to any endpoint and will accept and return JSON payloads.

#### Configuration

The client uses Faraday as the HTTP client and can be configured by providing a block on initialization:

```ruby
Zuorest::RestClient.new(
  server_url: "https://rest.apisandbox.zuora.com",
  access_key_id: "ZUORA_ACCESS_KEY",
  secret_access_key: "ZUORA_SECRET_ACCESS_KEY",
  client_id: "ZUORA_CLIENT_ID",
  client_secret: "ZUORA_CLIENT_SECRET"
) do |conn|
  conn.request :retry, max: 2
end
```

The object passed to the block is the Faraday connection which can be used to set middlewares and other options on the overall request.

#### URL Templates for Tracing

The RestClient supports URL templates for OpenTelemetry tracing. This helps prevent EUII or customer content from leaking in traces by providing a templated version of the URL.

URL templates must be explicitly provided using the `:attribute` format:

```ruby
# Explicitly providing a URL template
client.get("/v1/subscriptions/#{subscription_id}", url_template: "/v1/subscriptions/:id")
```

The URL template is stored in the request context and can be accessed by downstream middleware:

```ruby
class TracingUrlTemplate < ::Faraday::Middleware
  def call(env)
    template = env.request.context&.dig("url.template")
    OpenTelemetry::Common::HTTP::ClientContext.with_attributes("url.template" => template) do
      @app.call(env)
    end
  end
end
```

URL templates are also supported in Zuorest::Model classes:

```ruby
# Model class definition with URL template
class Zuorest::Model::Subscription < Zuorest::Model::Base
  zuora_rest_namespace "/v1/subscriptions/", url_template: "/v1/subscriptions/:id"
end

# URL template will be automatically used when finding resources
subscription = Zuorest::Model::Subscription.find(123)

# URL templates are also supported in relationships
class Zuorest::Model::Account < Zuorest::Model::Base
  has_many :subscriptions, 
           rest_namespace: "/v1/subscriptions/accounts/", 
           url_template: "/v1/subscriptions/accounts/:id"
end
```

#### Timeouts

Zuorest::RestClient provides the timeout options through the initializer as `open_timeout` and `timeout`. The defaults for these values is 60 seconds.

### Token Storage

By default, OAuth tokens are stored in memory within the REST client instance. This means that if you have multiple processes or instances of the client, each one will need to fetch its own token.

You can provide a custom token storage backend to share tokens between processes by implementing the `Zuorest::TokenStorage` interface:

```ruby
# Example using Rails.cache as a token storage backend
class RailsCacheTokenStorage < Zuorest::TokenStorage
  def get(key)
    Rails.cache.read(key)
  end

  def store(key, data)
    # Calculate expiration time - set to 1 hour before actual expiration
    # to ensure we don't use a token that's about to expire
    expires_in = data["expires_at"] ? data["expires_at"] - Time.now.to_i - 3600 : nil
    
    if expires_in && expires_in > 0
      Rails.cache.write(key, data, expires_in: expires_in)
    else
      Rails.cache.write(key, data)
    end
  end
end

# Use it with the client
rails_cache_storage = RailsCacheTokenStorage.new

client = Zuorest::RestClient.new(
  server_url: "https://rest.apisandbox.zuora.com",
  access_key_id: "ZUORA_ACCESS_KEY",
  secret_access_key: "ZUORA_SECRET_ACCESS_KEY",
  client_id: "ZUORA_CLIENT_ID",
  client_secret: "ZUORA_CLIENT_SECRET",
  token_storage: rails_cache_storage
)
```

Note that the token storage backend only needs to handle storing and retrieving the raw token data as a hash. The RestClient handles all the serialization and deserialization of OAuth tokens.

For performance reasons, the RestClient maintains a local in-memory cache of the token. This means that even when using a shared token storage backend, each client instance will fetch the token from the storage only once (until it expires), minimizing the number of storage reads.

## Development

### Setup and Testing

After checking out the repo, run `bin/setup` to install dependencies. Then, run `bundle exec rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

### Testing with the Sandbox Environment

To instantiate a client against `https://apisandbox.zuora.com` in the console, get the credentials from the `Zuora - meuse Staging (Sandbox Credentials)` entry in the gitcoin 1Password.

Run `bin/console` and initialize a new Zuorest client:

```ruby
Zuorest::Model::Base.zuora_rest_client = Zuorest::RestClient.new(
  server_url: "https://rest.apisandbox.zuora.com",
  access_key_id: "ZUORA_ACCESS_KEY",
  secret_access_key: "ZUORA_SECRET_ACCESS_KEY",
  client_id: "ZUORA_CLIENT_ID",
  client_secret: "ZUORA_CLIENT_SECRET"
)

# Test your client by making a request:
Zuorest::Model::Order.find "O-00000021"
```

### Testing in Dotcom

To test Zuorest changes in Dotcom while in development, update your Gemfile to point to your local changes:

```ruby
# For testing local changes
gem 'zuorest', path: '../path/to/local/zuorest'

# Or for testing from a specific branch
gem 'zuorest', github: 'github/zuorest', branch: 'your-branch-name'
```

### Release Process

To release a new version, update the version number in `version.rb`. Then:

#### GitHub Package Repository
- **Automatic (default):** Release to [GPR](https://github.com/orgs/github/packages) happens automatically via CI when a new version number is pushed to the `master` branch and the version does not exist as a tag.

### Adding New APIs

1. Check that it's not already addressed in the gem
2. Determine the category (e.g., product, payment, account, or new)
3. Add the API to the corresponding category
4. Add validation if needed
5. Add unit tests
6. Update version in `version.rb`
7. Merge changes to `master`
8. Wait for CI to publish or manually release
9. Update version number in Gemfile and run `bundle install`

### Validation

Input validation rules for GET and PUT methods:
- Length: 32 chars maximum
- IDs: Alphanumeric only (e.g., `2c92c0fa624bb1f20162694a4c7937ab`)
- Numbers: Alphanumeric plus hyphen (e.g., `A-S1234567`)


## API Reference

### Available Categories

The following API categories are supported:

* Account
* Action
* Contact
* Credit Balance Adjustment
* Import
* Invoice & Invoice Collect
* Notification History
* Orders
* Payment & Payment Methods
* Product & Rate Plans
* Refund
* RSA Signature
* Subscription
* Usage

### Available Endpoints

| Method | Name | URL | Usage | 
|--------|------|-----|-------|
| GET | get_payment_method | `/v1/object/payment-method/#{id}` | `zuora_client.get_payment_method(id)` |
| GET | get_invoice | `/v1/invoices/#{key}` | `zuora_client.get_invoice(key)` |
| GET | get_payment_method_snapshot | `/v1/object/payment-method-snapshot/#{id}` | `zuora_client.get_payment_method_snapshot(id)` |
| GET | get_refund | `/v1/object/refund/#{id}` | `zuora_client.get_refund(id)` |
| GET | get_subscription | `/v1/subscriptions/#{id}` | `zuora_client.get_subscription(id)` |
| GET | get_account | `/v1/object/account/#{id}` | `zuora_client.get_account(id)` |
| GET | get_usage_status | `/v1/usage/#{id}/status` | `zuora_client.get_usage_status(id)` |
| GET | get_product_rate_plan_charge | `/v1/object/product-rate-plan-charge/#{id}` | `zuora_client.get_product_rate_plan_charge(id)` |
| GET | get_import | `/v1/object/import/#{id}` | `zuora_client.get_import(id)` |
| GET | get_contact | `/v1/object/contact/#{id}` | `zuora_client.get_contact(id)` |
| GET | get_product | `/v1/object/product/#{id}` | `zuora_client.get_product(id)` |
| GET | get_payments | `/v1/transactions/payments/accounts/#{account_id}` | `zuora_client.get_payments(id, params, headers)` |
| GET | get_object_invoice | `/v1/object/invoice/#{id}` | `zuora_client.get_object_invoice(id)` |
| PUT | update_subscription | `/v1/subscriptions/#{id}` | `zuora_client.update_subscription(id, data, headers)` |
| PUT | update_payment_method | `/v1/object/payment-method/#{id}` | `zuora_client.update_payment_method(id, data, headers)` |
| PUT | update_payment | `/v1/object/payment/#{id}` | `zuora_client.update_payment(id, data, headers)` |
| PUT | update_object_account | `/v1/object/account/#{id}` | `zuora_client.update_object_account(id, data, headers)` |
| PUT | update_account | `/v1/accounts/#{id}` | `zuora_client.update_account(id, data, headers)` |
| PUT | cancel_subscription | `/v1/subscriptions/#{id}/cancel` | `zuora_client.cancel_subscription(id, data, headers)` |
| PUT | suspend_subscription | `/v1/subscriptions/#{id}/suspend` | `zuora_client.suspend_subscription(id, data, headers)` |
| PUT | resume_subscription | `/v1/subscriptions/#{id}/resume` | `zuora_client.resume_subscription(id, data, headers)` |
| POST | create_payment | `v1/object/payment` | `zuora_client.create_payment(data, headers)` |
| POST | create_invoice_collect | `/v1/operations/invoice-collect` | `zuora_client.create_invoice_collect(data, headers)` |
| POST | create_usage | `/v1/usage` | `zuora_client.create_usage(data, headers)` |
| POST | update_action | `/v1/action/update` | `zuora_client.update_action(data, headers)` |
| POST | create_product | `/v1/object/product` | `zuora_client.create_product(data, headers)` |
| POST | create_product_rate_plan | `/v1/object/product-rate-plan` | `zuora_client.create_product_rate_plan(data, headers)` |
| POST | create_action | `/v1/action/create` | `zuora_client.create_action(data, headers)` |
| POST | create_account | `/v1/accounts` | `zuora_client.create_account(data, headers)` |
| POST | create_object_account | `/v1/object/account` | `zuora_client.create_object_account(data, headers)` |
| POST | create_subscription | `/v1/subscriptions` | `zuora_client.create_subscription(data, headers)` |
| POST | create_credit_balance_adjustment | `/v1/object/credit-balance-adjustment` | `zuora_client.create_credit_balance_adjustment(data, headers)` |
| POST | query_action | `/v1/action/query` | `zuora_client.query_action(data, headers)` |
| POST | create_rsa_signature | `/v1/rsa-signatures` | `zuora_client.create_rsa_signature(data, headers)` |
| POST | create_refund | `/v1/object/refund` | `zuora_client.create_refund(data, headers)` |
| POST | create_contact | `/v1/object/contact` | `zuora_client.create_contact(data, headers)` |
| POST | create_payment_method | `/v1/object/payment-method` | `zuora_client.create_payment_method(data, headers)` |
| POST | get_product_id_for_name | `/v1/action/query` | `zuora_client.get_product_id_for_name(product_name)` |
| POST | create_authorization | `/v1/payment-methods/#{id}` | `zuora_client.create_authorization(id)` |
| POST | cancel_authorization | `/v1/payment-methods/#{id}/voidAuthorize` | `zuora_client.cancel_authorization(id)` |
| POST | email_invoice | `/v1/invoices/#{id}/emails` | `zuora_client.email_invoice(id, data, headers)` |
| POST | generate_billing_documents | `/v1/accounts/#{id}/billing-documents/generate` | `zuora_client.generate_billing_documents(id, data, headers)` |
| POST | update_object_invoice | `/v1/object/invoice/#{id}` | `zuora_client.update_object_invoice(id, body, headers)` |
| POST | create_order | `/v1/orders` | `zuora_client.create_order(body, return_ids: true|false, headers: headers)` |

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/github/zuorest.
