# Data Warehousing

Usage data is collected in the billing system and rolled up into various partitions in our Cosmos DB to power our usage charts and carry out invoice generation. However, this data in Cosmos DB is not directly accessible to downstream consumers such as revenue reporting and sales analytics. With this, we distribute our billing data to both [Kusto](../tools/azure-data-explorer-kusto.md) and [Trino](../tools/trino.md) ([data.githubapp.com](https://data.githubapp.com/)) via [Hydro messages](../tools/hydro.md).

## Table of Contents

- [Details](#details)
  - [Updates to data](#updates-to-data)

## Details

### Updates to data

Updates to existing data in the data warehouse should be done via a [data request](https://github.com/github/data/issues/new?template=data-request-.md).

If you are looking to backfill data as a one off task to the data warehouse, consider using our [transition job](../tools/transitions.md).
