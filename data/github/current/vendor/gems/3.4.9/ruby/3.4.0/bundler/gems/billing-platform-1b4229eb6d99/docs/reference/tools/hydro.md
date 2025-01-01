# Hydro

Hydro is used to ingest usage as well as to send usage data to [Kusto](./azure-data-explorer-kusto.md) and [Trino](./trino.md).

## Table of Contents

- [Details](#details)
  - [Usage data analytics](#usage-data-analytics)

## Details

### Usage data analytics

The following Hydro topics are used to distribute billing data:

- [billingplatform.v1.UsageLineItem](https://hydro.githubapp.com/kafka/clusters/potomac/topic?tab=schema&topic=billingplatform.v1.UsageLineItem)
- [billingplatform.v1.DiscountLineItem](https://hydro.githubapp.com/kafka/clusters/potomac/topic?tab=schema&topic=billingplatform.v1.DiscountLineItem)
- [billingplatform.v1.Invoice](https://hydro.githubapp.com/kafka/clusters/potomac/topic?tab=schema&topic=billingplatform.v1.Invoice)

Usage line item and discount line item messages are sent during usage ingestion where as the invoice messages are sent as we generate invoice for customers. This would be daily for Azure customers and monthly for Zuora customers.

We currently have a [2 year retention policy](https://github.com/github/hydro-schemas/blob/d3dc9d72bf567df4d4783ea7cf27a13816bc6dd1/topic-configuration/production/potomac/billingplatform.yaml#L29) for our data in both Trino and Kusto to help maintain a data coexistence with Meuse data for historical reporting purposes. Long term we would like to shorten the usage line item and discount line item retention policy to discourage building reports from these data sources.
