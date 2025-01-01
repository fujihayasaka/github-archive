# Actions Usage Metrics Export API Authentication

## Status

Proposed - 2024-04-17

## Context

The actions usage metrics export feature requires long running downloads of the files which can take greater than 10s for large customers, and can be almost a gigabyte of data for the largest customer. The Monolith enforces a timeout of 10s to ensure that services are not taking up more than their share of CPU, and handling file downloads in the API causes strain on the system and is not reliable or scalable. Below are the options we explored to support large usage data downloads.

## Comparison Chart

The below chart compares all of the options we considered.

| \#  | Option                                               | Description                                                                                                                           | Timeout    | Max size | Auth                                       | Decision | Reason                                                                                                                                                         |
| --- | ---------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- | ---------- | -------- | ------------------------------------------ | -------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | Background job + polling                             | Start the request, poll until complete, download once complete                                                                        | 10s        | 500MB    | Monolith                                   | ✅        | Can use Azure Blob Storage and SAS URLs for download. Keeps the heavy downloads<sup>1</sup> off the API and delegates downloads to Blob Storage. Balances simplicity with reliability and scalability.                                                               |
| 2   | Direct call to AUM API using signed URL              | Get signed URL from AUM through monolith, then call export API directly from dotcom to AUM                                            | None       | None     | Monolith for signed URL, HMAC for Moda API | ❌        | Same design that hosted-compute insights uses for [network logs](https://github.com/github/security-reviews/issues/1163), supports long operations and large data in the future, requires custom auth scheme (<https://github.com/github/security-reviews/issues/1394>), causes strain on API. |
| 3   | Multiple requests in parallel, join data client-side | Split the dotcom requests into N requests of pages of M items, combine it all in the client                                           | 10s        | 500MB    | Monolith                                   | ❌        | Poor manageability, too much logic in front-end                                                                                                                |
| 4   | Require user to filter down the data set             | If total items is > threshold, show a message to the user to filter down the results                                                  | 10s        | 500MB    | Monolith                                   | ❌        | Poor user experience                                                                                                                                           |
| 5   | Extend timeout time in dotcom                        | There is a way to override dotcom’s timeout [here](https://github.com/github/github/blob/master/lib/github/config/request_timeout.rb) | Adjustable | 500MB    | Monolith                                   | ❌        | Not recommended, holds up unicorns, needs exceptions, still has size limitations                                                                               |
| 6   | Compress data to reduce size                         | Compress the export data going from AUM to monolith                                                                                   | 10s        | 500MB    | Monolith                                   | ❌        | The data is already gzip compressed                                                        |

<sup>1 - According to [Kusto](https://dataexplorer.azure.com/clusters/ghdwprod.eastus/databases/hydro?query=H4sIAAAAAAAAA3VSTW%2FUMBA97%2F4Kq5cmaBH%2BjJPDHgCBtAdaVJYTQpF3M%2B0aknhlO02D%2BPGM05aWrbjE4zcz702epzMRvDWt%2FQVNfWthzM7fvt9uLi%2B%2B1EMwN1D%2FcLtQd66Ph3aqb9l5vvxNxgN4IB6OLtjo%2FHQ59uA3DbE9yZaLSipVKl2uMKxYhYdSvOIF1RgyprhKkOZMCJ1CrhillCeQaVlyLVMoKl4xmUg4poVmNHUrzoWSiahATiokw1AXTKoipbnmqqjK1CWwQKQeqYVKQzCBQoWaJbXGG51RxiktVJk0maxKRfksJJimUlC9TP8LdxH6hozO%2F7xu3fjRtvDZxMN6ZwIUsm5g7xqoowvR2%2F4mO61LFGHoOuPR5eViEV007SfbDxHCGhPZcyBH9QWa%2FuEO9kO0rr8v%2BQfJsWQ34efpCTZN6jtVPsUuTAfrv3OGY2vji2lX5OzNWf7tNfv%2BOMrXkF4X%2BmivLfgHcKb6jwEP6bnfDz0ux3Y6wtPtakCu7h44XaLnXpErN4b13mF5lq%2FINtn0bnp0DQKS4PrWjYmmDlifvcpzsptebmYidT6mXKIkDYT9HwMEY976AgAA), Itau has 4.2M rows and 876MB of job data for 1 year uncompressed and not including repository names. Even with polling we would have to resolve repositories and add them to the CSV, so we still risk timing out at 10s.<br/></sup>

## Decision

We plan to accomplish this by going with option #1 - starting an export asynchronously and giving the user an export ID to poll to check the status through the monolith. Once the status returns `complete`, the response will contain the blob SAS URL to download the file directly from Azure Blob Storage.

Everything (except the blob storage file download) will flow through the monolith. This is the proposed flow:

1. User kicks off an export to the service through dotcom --> monolith --> private AUM Moda API
2. Private AUM Moda API:
    1. Generates a export ID and immediately returns it to the client
    2. Kicks off a background job to query the data for the org+export type+filters
    3. Stores the file in blob storage with the org ID and export ID in the name
    4. Updates the export status for `OWNER_ID + export ID` to mark the job as complete
3. User polls for export status via dotom --> monolith --> private AUM Moda API
    1. Private AUM Moda API checks the status for the `OWNER_ID + export ID`
    2. If complete, generate an Azure Blob Storage SAS URL to `owner-<OWNER_ID>/<export-id>.csv` and return
    3. If not complete, returns either pending or failed status
4. User gets complete status and SAS URL, and downloads the CSV file directly from blob storage

Other notes:

- We are planning on setting up policies to expire the blob after an hour and have the SAS token expire after 10 minutes.
- There is no PII in the data being exported, and all of this data is what we display in the UI to the user already.
- Everything is partitioned by OWNER_ID, which comes in request from the monolith --> private AUM API
