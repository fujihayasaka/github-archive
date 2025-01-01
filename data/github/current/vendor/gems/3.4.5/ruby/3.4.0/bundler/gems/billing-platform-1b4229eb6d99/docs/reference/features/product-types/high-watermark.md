# High Watermark

> [!NOTE]
> High watermark billing only encompasses GHEC and GHAS products. We [migrated Copilot to default billing](https://github.com/github/metered-billing/discussions/88) on May 1st.

High watermark billing is a method of composite billing in which the customer is billed for the highest number of any unit consumed at the same time over the course of the billing cycle. Any seat cancellations that occur during the billing cycle do not take affect until the end of the month, meaning that in all cases the user is billed for the entire month.

## Table of Contents

- [Terminology](#terminology)
- [Details](#details)
  - [How to integrate](#how-to-integrate)
  - [High watermark products can only be used with user-based cost centers](#high-watermark-products-can-only-be-used-with-user-based-cost-centers)

## Terminology

- **Composite billing**: Refers to products that bill based on a unit over time (e.g., Byte-Hour, GiB-Month, etc.), both high watermark + watermark included.
- **Delta event** - When a seat is added or removed and data is sent to billing platform
- **High watermark billing**: Over the course of the billing cycle the customer is billed for the highest number of seats (or any unit) consumed at any given time over the course of a given billing cycle.
- **License/Seat** - The individual unit assigned to a single user
- **Watermark billing**: The customer is billed for the current amount of seats (or any unit) for every hour (or any interval of time) over the course of the billing cycle.

## Details

### How to integrate

[Billing platform integration guide](https://github.com/github/metered-billing/blob/main/product-teams-integration/self_serve_integration_guide.md#creating-products-and-skus-in-stafftools).

Billing platform accepts data when licenses are created and removed, meaning that it is an event based system. Unlike Meuse, where partner teams would send bulk license data on a schedule, product teams will only send usage data when a customer’s seat count changes as Delta Events. Billing Platform will then be responsible for keeping track of high watermarking and prorating seats as delta events are ingested.

The delta event will be emitted via hydro and the quantity will be either 1.0 (license added) or -1.0 (license removed). This is an example message:

```
 {
      sku: "sku_name", # name of the sku
      quantity: quantity, # either 1 or -1
      usage_at: Google::Protobuf::Timestamp.new(seconds: DateTime.now.utc.to_i, nanos: 0),
      source_uri: GlobalID.create(T.must(business).customer).to_s, # we don't use this information,
      usage_uuid: create_billing_message_uuid(prefix), # must be unique so that billing platform can be idempotent
      entity: {
        customer_id: T.must(business).customer_id,
        actor_id: user_id, # the ID of the actor assigned a license
      }
    }
```

> [!NOTE]
> Billing platform currently can't ingest `organization_ids` for high watermark meter, they will be discarded if sent.

### High watermark products can only be used with user-based cost centers

One of Billing Platform's new features is [cost centers which you can read more about here](./cost-centers.md). High watermark products can only be used with user-based cost centers. Any organization/repository based cost centers won't have high watermark usage show up unless the individual user IDs are also added to the cost center.
