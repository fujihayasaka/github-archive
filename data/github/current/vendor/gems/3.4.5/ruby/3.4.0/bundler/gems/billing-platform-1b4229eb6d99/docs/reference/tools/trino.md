# Trino

Trino is the distributed SQL engine for big data analytics. It can be queried through [Data-Dot](https://data.githubapp.com/). This is where billing data is currently sent to for data analytics through [Hydro](hydro.md).

## Table of Contents

- [Details](#details)
  - [Data warehousing with Trino](#data-warehousing-with-trino)
- [References](#references)

## Details

### Data warehousing with Trino

The long term goal is to remove billing data from Trino in favor of [Kusto](azure-data-explorer-kusto.md). At the time of writing we had to also send data to Trino to allow revenue and reporting to maintain data coexistence with billing platform and Meuse for reporting purposes. With this, there are no Trino queries that we recommend you use 😉

## References

- [The Hub: About the Data Warehouse](https://thehub.github.com/guides/data/data-warehouse-overview/)
