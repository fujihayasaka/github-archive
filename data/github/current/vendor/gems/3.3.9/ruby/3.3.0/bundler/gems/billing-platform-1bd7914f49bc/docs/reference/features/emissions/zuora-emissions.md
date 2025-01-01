# Zuora Emissions

Zuora emissions are generated for customers that are billed through Zuora. Each customer's usage for the month is sent to Zuora on the 1st of next month. To do this, we generate a billing platform Invoice document stored in Cosmos. These are then converted to Zuora Usage Records and uploaded to Zuora.

## Table of Contents

- [Details](#details)
  - [Invoice generation](#invoice-generation)
- [Troubleshooting](#troubleshooting)
  - [Query all invoices to be processed for the month](#query-all-invoices-to-be-processed-for-the-month)
  - [Query the invoice of a particular customer](#query-the-invoice-of-a-particular-customer)
  - [Re-generate and re-emit usage](#re-generate-and-re-emit-usage)
- [FAQ](#faq)
- [References](#references)

## Details

### Invoice generation

1. Cron scheduler runs everyday 1 am UTC (8:00 pm EST / 9:00 pm EDT)  and runs the NewInvoiceGeneration Job with  partition key of the form `monthly:year:previous month`. This job creates the invoice generation request to the Request Handler's aqueduct queue.
2. The Request Handler processes this message and calls the scheduleInvoiceGeneration on the Invoice engine. This checks the active invoice partitions for the month. All customers who had usage during the month will have an entry here. It then schedules a invoice generation job for each of those customers.
3. The Invoice generation handler  creates a new invoice document for each customer and uploads it Zuora. It also updates the active partition with the ProcessedAt timestamp and creates an entry in the submitted partition.

![invoice generation](/docs/images/invoice_generation.jpg)

> [!NOTE]
> If we receive late usage to the billing platform after we've emitted amount for the month to Zuora, the next invoice generation run would emit only the difference,(i.e) the late usage value to Zuora. This [issue](https://github.com/github/gitcoin/issues/12092) documents the case and has an example.

## Troubleshooting

### Query all invoices to be processed for the month

`SELECT * FROM c where c.partitionKey="invoices:active:2023:8"`
This returns a reference to all the individual customer invoice partitions that are active and will be processed . Each of these have a ProcessedAt field which should be null now. After 1 am UTC Sep 1st,  each of those referenced partitions should have an invoice document and ProcessedAt field updated

### Query the invoice of a particular customer

```
SELECT * FROM c where c.partitionKey = "customer:<customer_id>:invoices" AND c.id="customer:<customer_id>:invoices:2023:8"

```

### Re-generate and re-emit usage

If invoice was generated previously, its active partition will have ProcessedAt value set to a timestamp and also it will have a submitted partition entry. We manually reset these to re-generate and emit to zuora

1. Find active partition for a particular customer:

`SELECT * FROM c where c.partitionKey="invoices:active:2023:8" and c.id="customer:1274158:invoices:2023:8"`

```
[
 {
 "partitionKey": "invoices:active:2023:8",
 "id": "customer:1274158:invoices:2023:8",
 "ProcessedAt": "2023-09-01T15:48:15.754340317Z",
 "_rid": "5mFXAK7x5hryAQAAAABiCA==",
 "_self": "dbs/5mFXAA==/colls/5mFXAK7x5ho=/docs/5mFXAK7x5hryAQAAAABiCA==/",
 "_etag": "\"5914454d-0000-0100-0000-64f207bf0000\"",
 "_attachments": "attachments/",
 "_ts": 1693583295
 }
]
```

Set the ProcessedAt field to null and save record.

2. Find submitted partition and delete that entry
`SELECT * FROM c where c.partitionKey="invoices:submitted:2023:8" and c.id="customer:1274158:invoices:2023:8"`

```
[
 {
 "partitionKey": "invoices:submitted:2023:8",
 "id": "customer:1274158:invoices:2023:8",
 "SubmittedAt": "2023-09-01T15:48:15.952601763Z",
 "_rid": "5mFXAK7x5hqazAkAAACQAQ==",
 "_self": "dbs/5mFXAA==/colls/5mFXAK7x5ho=/docs/5mFXAK7x5hqazAkAAACQAQ==/",
 "_etag": "\"1c0230f0-0000-0100-0000-64f207c00000\"",
 "_attachments": "attachments/",
 "_ts": 1693583296
 }
]
```

Delete this partition entry

3. regenerate invoice from stafftools UI

https://admin.github.com/stafftools/enterprises/shopify/billing/invoices. To re-generate for particular month, enter its value.

## FAQ

- **What are some examples of logs to look for?**
  - [ScheduleInvoiceGeneration Start](https://splunk.githubapp.com/en-US/app/gh_reference_app/search?q=search%20index%3Dbilling%20kube_namespace%3Dbilling-platform*%20%22ScheduleInvoiceGeneration%20Start%22&display.page.search.mode=smart&dispatch.sample_ratio=1&workload_pool=Standard&earliest=-24h%40h&latest=now&sid=1693502228.1987705_BBFEADC1-13E7-469C-AD3C-290EFFB13C63)
  - [createInvoiceGenerationBatchJob](https://splunk.githubapp.com/en-US/app/gh_reference_app/search?q=search%20index%3Dbilling%20kube_namespace%3Dbilling-platform*%20%22createInvoiceGenerationBatchJob%22&display.page.search.mode=smart&dispatch.sample_ratio=1&workload_pool=Standard&earliest=-24h%40h&latest=now&sid=1693503223.1987871_BBFEADC1-13E7-469C-AD3C-290EFFB13C63)

## References

- [Invoice generation dashboard](https://app.datadoghq.com/dashboard/646-msn-qic?refresh_mode=sliding&from_ts=1694798396965&to_ts=1694801996965&live=false&tile_focus=2982142941825084)
- [Zuora emission dashboard](https://app.datadoghq.com/dashboard/646-msn-qic?refresh_mode=sliding&from_ts=1694799154729&to_ts=1694802754729&live=false&tile_focus=2754157283473964)
- [ADR: Daily Zuora emissions](https://github.com/github/gitcoin/blob/main/docs/technical/architecture-decision-record/0040-daily-zuora-emissions-on-billing-platform-vnext.md)
