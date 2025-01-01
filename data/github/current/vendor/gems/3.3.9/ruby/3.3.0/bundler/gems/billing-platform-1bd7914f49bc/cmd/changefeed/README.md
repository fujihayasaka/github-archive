# Billing Platform Change Feed

.Net Cosmos DB Change Feed Processor for Billing Platform. See https://learn.microsoft.com/en-us/azure/cosmos-db/change-feed for more information.

## Usage

In the root of billing platform, run:

```
./script/changefeed
```

This will trigger the changefeed processor to run on any changes in the monitored container. All changes that have been seen will be added to the lease container. Bumping the change feed `version` will create new containers, allowing you to re-process prior changes.
