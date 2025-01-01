# Zuora Emissions Daily

Zuora emissions are generated daily for customers that are billed through Zuora. Each customer's usage for the day is sent to Zuora on the following day. To do this, we generate a billing platform Emission document stored in Cosmos. These are then converted to Zuora Usage Records and uploaded to Zuora.

## Table of Contents

- [Details](#details)
  - [Emission generation](#emission-generation)
- [Troubleshooting](#troubleshooting)
  - [Query all emission processed for a particular customer for the month](#query-all-emission-processed-for-a-particular-customer-for-the-month)
  - [Query the emission of a particular customer for a specific day](#query-the-emission-of-a-particular-customer-for-a-specific-day)
  - [Re-generate and re-emit usage](#re-generate-and-re-emit-usage)
- [FAQ](#faq)
- [References](#references)

## Details

### Emission generation

1. Cron scheduler runs every day at 5:00 AM UTC (12:00 AM EST / 1:00 AM EDT) and runs the NewEmissionGeneration Job with partition key of the form `daily:year:month:day`. This job creates the emission generation request to the Request Handler's aqueduct queue.
2. The Request Handler processes this message and calls the scheduleEmissionGeneration on the Emission engine. This checks the customer zuora emission daily rollup  partitions for the day. All customers who had usage during the day will have an entry here. It then schedules an emission generation job for each of those customers.
3. During the `EmissionHandler` process, discount line items are retrieved and combined with any late discount records, and cost center details are incorporated for cost center proxies. A new Emission object is created, and the usage records are consolidated by product/SKU and saved in the emission partition.
4. A process within this handler is triggered to process the emission records into Zuora upload usage records. It consolidates multiple users into batches based on the number of records and payload size. When these parameters are met, the batch status is updated, a `ZuoraEmissionBatchStatus` job is scheduled for the completed batch, and a new batch is created.
5. The `ZuoraBatchEmissionHandler` receives a message to process a batch. It retrieves the relevant `ZuoraBatchEmission` records, which are already formatted for Zuora. The formatted usage data is then uploaded to the Zuora API.

![Emission process](/docs/images/zuora-daily-emission.png)

> [!NOTE]
> If we receive late usage to the billing platform after we've emitted the amount for the day to Zuora, the late usage item is detected and processed in the next emission generation run. The late usage value is emitted to Zuora as a additional record. This ensures that all usage data, even if received late, is accounted for and billed correctly.

## Troubleshooting

### Query all emission processed for a particular customer for the month

`SELECT * FROM c where c.partitionKey="3900030:Emission:2025:2"`
This returns a reference to all the individual customer emission partitions that have been emitted. Each of these have a Status field which should be 1 (submitted).

### Query the emission of a particular customer for a specific day

```
SELECT * FROM c where c.partitionKey = "<customer_id>:Emission:<year>:<month>" AND c.id="<customer_id>:Emission:<year>:<month>:<day>"
```

### Re-generate and re-emit usage


## FAQ

- **What are some examples of logs to look for?**
  - [EmissionHandler](https://splunk.githubapp.com/en-US/app/gh_reference_app/search?q=search%20index%3Dbilling%20EmissionHandler&display.page.search.mode=smart&dispatch.sample_ratio=1&workload_pool=Standard&earliest=-24h%40h&latest=now&sid=1739484621.351282_336CB4DA-A9B1-4141-AFCD-E3812CF78E50)
  - [createInvoiceGenerationBatchJob](https://splunk.githubapp.com/en-US/app/gh_reference_app/search?q=search%20index%3Dbilling%20kube_namespace%3Dbilling-platform*%20%22createInvoiceGenerationBatchJob%22&display.page.search.mode=smart&dispatch.sample_ratio=1&workload_pool=Standard&earliest=-24h%40h&latest=now&sid=1693503223.1987871_BBFEADC1-13E7-469C-AD3C-290EFFB13C63)

## References

- [Invoice generation dashboard](https://app.datadoghq.com/dashboard/646-msn-qic?refresh_mode=sliding&from_ts=1694798396965&to_ts=1694801996965&live=false&tile_focus=2982142941825084)
- [Zuora emission dashboard](https://app.datadoghq.com/dashboard/646-msn-qic?refresh_mode=sliding&from_ts=1694799154729&to_ts=1694802754729&live=false&tile_focus=2754157283473964)
- [ADR: Daily Zuora emissions](https://github.com/github/gitcoin/blob/main/docs/technical/architecture-decision-record/0040-daily-zuora-emissions-on-billing-platform-vnext.md)
