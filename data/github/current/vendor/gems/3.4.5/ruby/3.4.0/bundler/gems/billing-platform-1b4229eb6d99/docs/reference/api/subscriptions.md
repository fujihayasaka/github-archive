# Subscriptions

The [subscriptions API](https://github.com/github/billing-platform/blob/main/lib/api/subscriptions.go) is an API exposed to dotcom via the [ruby client](https://github.com/github/github/blob/master/packages/billing/app/models/billing/platform/api/client.rb#L21) that allows interacting with a customer's subscriptions in billing platform. There is an endpoint to Add and Remove a license, which has the same effect as creating a +1 or -1 event via hydro.

## Table of Contents

- [Details](#details)
  - [Subscriptions in Billing Platform](#subscriptions-in-billing-platform)
- [Troubleshooting](#troubleshooting)
  - [Testing the subscriptions API in dotcom](#testing-the-subscriptions-api-in-dotcom)
- [References](#references)

## Details

### Subscriptions in Billing Platform

```
partitionKey: {customerID}:highWatermark:{sku}
id: subscription:123
subscription_status: 0 //active
```

This is what a single subscription item would look like in billing platform, the `subscription:123` in the ID corresponds to the user ID of the user assiged that license. The subscription status shows whether or not the subscription is active or cancelled. To cancel a subscription, you would need to send a -1 event to billing platform (or call RemoveLicense using this API).

## Troubleshooting

### Testing the subscriptions API in dotcom

This API can be called directly from a rails console locally for testing.

First, set up a dotcom/billing-platform codespace as outlined [here](https://github.com/github/billing-platform/blob/main/docs/how-to-guides/how-to-run-billing-platform-in-dotcom-codespaces.md).

Then, open up a new rails console and create a new billing platform client

```ruby
bin/rails c
billing_client = ::Billing::Platform::Client.new
```

Then you can test out the various endpoints.

```ruby
current_seats = billing_client.get_all_subscribed_items(usage_entity_id: {example customer ID}, sku: {example sku})
```

## References

- [Subscriptions API definition](https://github.com/github/billing-platform/blob/main/lib/api/subscriptions.go)
- [Billing Platform Ruby client](https://github.com/github/github/blob/master/packages/billing/app/models/billing/platform/api/client.rb#L21)
