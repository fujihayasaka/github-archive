# Cosmos id / partitionKey Structure For Our Records

When looking for records in Cosmos, it can be useful to know what the structure of these identifying fields look like.

We also have a [dashboard](https://app.datadoghq.com/dashboard/dvs-avz-mre/billing-cosmosdb?fromUser=false&refresh_mode=sliding&view=spans&from_ts=1714421757816&to_ts=1715026557816&live=true) to help us understand RU consumption by partition template.

_When adding records to this resource, please try to follow format and keep things alphabetized_

## Table of Contents

- [Azure Emission](#azure-emission)
- [Budgets](#budgets)
- [Cost Centers](#cost-centers)
- [Customers](#customers)
- [Discounts](#discounts)
- [Invoices](#invoices)
- [Products](#products)
- [Repositories](#repositories)
- [TopOrgRepo](#top-org-repo)
- [Usage](#usage)
- [Usage Reports](#usage-reports)
- [Watermark](#watermark)
- [High Watermark](#high-watermark)
- [Zuora Emission](#zuora-emission)

---

## Azure Emission

<details>

<summary>Expand</summary>

### Azure Emission Rollup

Each roll up item represents an aggregate total of an Azure customer's usage for the specified SKU in a one day period. These records are used to send a customer's usage to Azure on a daily basis. Certain fields like the `ActorId`, `OrganizationId` and `RepositoryId` will not be accurate for these items, since each item represents the total usage for the SKU across all actors, orgs and repos belonging to the customer. See our [Azure emission docs](https://github.com/github/billing-platform/blob/main/docs/reference/features/emissions/azure-emissions.md) for more details.

|                       |                                                      |
| --------------------- | ---------------------------------------------------- |
| id:                   | `"[customer_id]:[product_sku]:[year]:[month]:[day]"` |
| id example:           | `"9370820:actions_linux:2023:6:15"`           |
| partitionKey:         | `"[year]:[month]:[day]:byAzureEmission"`             |
| partitionKey example: | `"2023:6:15:byAzureEmission"`                        |

<details>

<summary>Example Item</summary>

``` json
[{
  "AppliedCostPerQuantity": 8000000,
  "BilledAmount": 80088000000,
  "EntityDetail": {
    "ActorId": 19912012,
    "CostCenterDetail": {
      "CostCenterState": 0,
      "CostCenterUUID": "",
      "EnterpriseCustomerId": "9370820",
      "IsCostCenterProxy": false
    },
    "CustomerId": "9370820",
    "OrganizationId": 95450610,
    "RepositoryId": 776107388
  },
  "FractionalQuantity": 0,
  "FullQuantity": 10011000000000,
  "Pricing": {
    "AzureMeterId": "3dbfec75-284c-4c89-8c9c-0d395be81a0c",
    "EffectiveAt": 1689366600,
    "EffectiveDatePrices": [],
    "FreeForPublicRepos": true,
    "FriendlyName": "Actions Linux",
    "MeterType": 0,
    "Price": 8000000,
    "Product": "actions",
    "Sku": "actions_linux",
    "UnitType": 2,
    "id": "actions_linux",
    "partitionKey": "pricing"
  },
  "Quantity": 10011000000000,
  "SourceUri": "gid://git-hub/CheckRun/24079854681",
  "UsageAt": 1713744012393,
  "_attachments": "attachments/",
  "_etag": "\"1601b7a7-0000-0100-0000-6626f9690000\"",
  "_rid": "5mFXAK7x5hqsDZEAAAAoCg==",
  "_self": "dbs/5mFXAA==/colls/5mFXAK7x5ho=/docs/5mFXAK7x5hqsDZEAAAAoCg==/",
  "_ts": 1713830249,
  "id": "1061737:actions_linux:2023:6:15",
  "partitionKey": "2023:6:15:byAzureEmission"
}]

```

</details>

### Azure Emission Records

These items store information about an Azure customer's usage that have been submitted to Azure for a given SKU for the day specified in the id. The partition will include one item for every day in the month that the customer had usage for the SKU.
|                       |                                                                    |
| --------------------- | ------------------------------------------------------------------ |
| id:                   | `"[customer_id]:[product_sku]:azureEmission:[year]:[month]:[day]"` |
| id example:           | `"9370820:actions_linux:azureEmission:2023:6:27"`                  |
| partitionKey:         | `"[customer_id]:[product_sku]:azureEmission:[year]:[month]"`       |
| partitionKey example: | `"9370820:actions_linux:azureEmission:2023:6"`                     |



<details>

<summary>Example Item</summary>

```json
[{
  "AzurePartitionKey": "4b16c61d-0bda-44b1-b04a-983a486d4ad3",
  "ErrorMessage": "",
  "GrossQuantity": 10011,
  "MeterId": "3dbfec75-284c-4c89-8c9c-0d395be81a0c",
  "Quantity": 6345,
  "Status": 2,
  "SubscriptionId": "57997474-7983-4d65-a2e3-83410c0e43b3",
  "_attachments": "attachments/",
  "_etag": "\"2b01296d-0000-0100-0000-66276e0f0000\"",
  "_rid": "5mFXAK7x5hpw840AAAAUAA==",
  "_self": "dbs/5mFXAA==/colls/5mFXAK7x5ho=/docs/5mFXAK7x5hpw840AAAAUAA==/",
  "_ts": 1713860111,
  "id": "9370820:actions_linux:azureEmission:2023:6:27",
  "partitionKey": "9370820:actions_linux:azureEmission:2023:6"
}]

```

</details>

</details>

## Budgets

<details>

<summary>Expand</summary>

### Budget

Each item represents a budget for a customer. There are various budget target types (i.e. customer, cost center, etc.) but all budgets must be scoped to a single product.

|                       |                                                                            |
| --------------------- | -------------------------------------------------------------------------- |
| id:                   | `"customer:[customer_id]:budgets:[budget_target_type]:[budget_target_id]:product:[:product_name]"` |
| id example:           | `"customer:421873:budgets:customer:421873:product:actions"`                              |
| partitionKey:         | `"customer:[customer_id]:budgets"`                                         |
| partitionKey example: | `"customer:421873:budgets"`                                                |

<details>

<summary>Example Item</summary>

```json

{
  "BudgetLimitType": 2,
  "CustomerId": "421873",
  "PricingTargetId": "actions",
  "PricingTargetType": 1,
  "RecipientUserIDs": [
    "12898988",
    "72952982"
  ],
  "TargetAmount": 50000000000000,
  "TargetId": "421873",
  "TargetType": 7,
  "Uuid": "d45dfa1d-04b3-4fb9-ac73-9ecc53eb22e6",
  "WillAlert": true,
  "_attachments": "attachments/",
  "_etag": "\"2e00fa6e-0000-0100-0000-662bd3cd0000\"",
  "_rid": "5mFXAK7x5hrhHBoAAACYCA==",
  "_self": "dbs/5mFXAA==/colls/5mFXAK7x5ho=/docs/5mFXAK7x5hrhHBoAAACYCA==/",
  "_ts": 1714148301,
  "id": "customer:421873:budgets:customer:421873:product:actions",
  "partitionKey": "customer:421873:budgets"
}

```

</details>

### BudgetState

Each item tracks the customer's usage towards their budget for the given target type and product for the given time period.

|                       |                                                                                           |
| --------------------- | ----------------------------------------------------------------------------------------- |
| id:                   | `"budgetState"`                                                                           |
| partitionKey:         | `"customer:[customer_id]:budgets:[budget_target_type]:[budget_target_id]:product:[product_name]:[year]:[month]"` |
| partitionKey example: | `"customer:1061737:budgets:customer:1061737:product:actions:2024:4"`                                      |

<details>

<summary>Example Item</summary>

```json

{
  "CurrentAmount": 50772163576843, // Amount of usage applied towards the budget
  "IsFullyFunded": false,
  "Quantity": 7164430048784171,
  "TargetAmount": 100000000000000, // The budget amount set by the customer
  "ThresholdMet": {
    "Alertable": false,
    "MinimumUsagePercentage": 0,
    "Name": ""
  },
  "_attachments": "attachments/",
  "_etag": "\"77010fb0-0000-0100-0000-663150880000\"",
  "_rid": "5mFXAK7x5hrfT4AAAAAUAw==",
  "_self": "dbs/5mFXAA==/colls/5mFXAK7x5ho=/docs/5mFXAK7x5hrfT4AAAAAUAw==/",
  "_ts": 1714507912,
  "id": "budgetState",
  "partitionKey": "customer:1061737:budgets:customer:1061737:product:actions:2024:4"
}

```

</details>

</details>

## Cost Centers

<details>

<summary>Expand</summary>

### Customer Cost Centers

Each item includes the details for a customer's cost center.

|                       |                                          |
| --------------------- | ---------------------------------------- |
| id:                   | `"[uuid]"`                               |
| id example:           | `"af7bbc6f-edb1-4f82-879b-8933128208e3"` |
| partitionKey:         | `"customer:[customer_id]:costCenters"`   |
| partitionKey example: | `"customer:7464727:costCenters"`         |

<details>

<summary>Example Item</summary>

```json

{
  "CostCenterState": 0,
  "Customer": {
    "AzureAccountId": "",
    "BillForPublicRepoUsage": false,
    "BillingTarget": 0,
    "CostCenterState": 0,
    "CostCenterUUID": "",
    "DiscountPlanName": "",
    "EffectiveAt": 0,
    "EnabledProducts": [],
    "EnterpriseCustomerId": "7464727",
    "HasPaymentMethod": false,
    "HasZuoraSubscription": false,
    "IsBillingLocked": false,
    "IsCostCenterProxy": false,
    "TradeScreening": null,
    "ZuoraAccountId": "",
    "ZuoraAccountNumber": "",
    "id": "customer",
    "partitionKey": "customer:7464727"
  },
  "Name": "MPTestCC",
  "Resources": [
    {
      "Id": "129203213",
      "Type": 4
    },
    {
      "Id": "632032489",
      "Type": 3
    }
  ],
  "TargetId": "4747da6d-b46f-4855-ad27-d894ed1ffa8c",
  "TargetType": 4,
  "UUID": "af7bbc6f-edb1-4f82-879b-8933128208e3",
  "_attachments": "attachments/",
  "_etag": "\"34002332-0000-0100-0000-660587490000\"",
  "_rid": "5mFXAK7x5hoQGBcAAAAYBw==",
  "_self": "dbs/5mFXAA==/colls/5mFXAK7x5ho=/docs/5mFXAK7x5hoQGBcAAAAYBw==/",
  "_ts": 1711638345,
  "id": "af7bbc6f-edb1-4f82-879b-8933128208e3",
  "partitionKey": "customer:7464727:costCenters"
}

```

</details>

### Customer Cost Center Resource Lookup Records

|                       |                                                                      |
| --------------------- | -------------------------------------------------------------------- |
| id:                   | `"byTarget:azure_subscription:[uuid]"`                               |
| id example:           | `"byTarget:azure_subscription:f1914875-a159-4a69-beb0-b1935f5b9f4f"` |
| partitionKey:         | `"customer:[customer_id]:costCenters"`                               |
| partitionKey example: | `"customer:7464727:costCenters"`                                     |

_Note that cost centers without an Azure subscription ID added will have an ID of `byTarget:azure_subscription:`_

</details>

## Customers

<details>

<summary>Expand</summary>

### Customer Records

Each item includes the details for a customer

|                       |                                          |
| --------------------- | ---------------------------------------- |
| id:                   | `"customer"`                               |
| id example:           | `"customer"` |
| partitionKey:         | `"customer:[customer_id]"`   |
| partitionKey example: | `"customer:14853641"`         |

<details>

<summary>Example Item</summary>

```json

{
  "partitionKey": "customer:14853641",
  "id": "customer",
  "EnterpriseCustomerId": "14853641",
  "CostCenterUUID": "",
  "IsCostCenterProxy": false,
  "CostCenterState": 0,
  "BillingTarget": 1,
  "AzureAccountId": "",
  "ZuoraAccountId": "",
  "ZuoraAccountNumber": "A03453113",
  "EnabledProducts": [
    "actions",
    "codespaces",
    "copilot",
    "git_lfs",
    "packages"
  ],
  "EffectiveAt": 1723742997,
  "DiscountPlanName": "team",
  "BillForPublicRepoUsage": false,
  "HasPaymentMethod": true,
  "HasZuoraSubscription": true,
  "IsBillingLocked": false,
  "IsStaffOwned": false,
  "TradeScreening": {},
  "_rid": "5mFXAK7x5hrONNEAAABnCQ==",
  "_self": "dbs\/5mFXAA==\/colls\/5mFXAK7x5ho=\/docs\/5mFXAK7x5hrONNEAAABnCQ==\/",
  "_etag": "\"7700358f-0000-0100-0000-6705ab310000\"",
  "_attachments": "attachments\/",
  "_ts": 1728424753
}

```

</details>

</details>



## Discounts

<details>

<summary>Expand</summary>

### Customer Discount Records

Each record displays the details of a configured discount for the specified customer. Note: plan discounts and public repo discounts will not have records with this partition key and id combination. For more details, see the [discount docs](https://github.com/github/billing-platform/blob/main/docs/reference/features/discounts.md).

|                       |                                          |
| --------------------- | ---------------------------------------- |
| id:                   | `"[uuid]"`                               |
| id example:           | `"ea27218c-4202-444a-8df6-ffde7aa1efcc"` |
| partitionKey:         | `"customer:[customer_id]:discounts"`     |
| partitionKey example: | `"customer:7464727:discounts"`           |

<details>

<summary>Example Item</summary>

```json
{
    "partitionKey": "customer:1:discounts",
    "id": "165326b6-f4c6-4e51-b917-16895d7213fc",
    "Uuid": "165326b6-f4c6-4e51-b917-16895d7213fc",
    "CustomerId": "1",
    "Percentage": 0,
    "TargetAmount": 5000000000,
    "Targets": [
        {
            "Id": "actions_linux_16_core",
            "Type": 1
        }
    ],
    "StartDate": 1714521600000,
    "EndDate": 1717113600000,
    "_rid": "9xN8APCQWaE-AAAAAAAAAA==",
    "_self": "dbs/9xN8AA==/colls/9xN8APCQWaE=/docs/9xN8APCQWaE-AAAAAAAAAA==/",
    "_etag": "\"13001d27-0000-0700-0000-6639111f0000\"",
    "_attachments": "attachments/",
    "_ts": 1715015967
}

```

</details>

### Customer Discount State

These items track the aggregate amount of usage applied towards a given discount for the provided one month period.

|                       |                                                                            |
| --------------------- | -------------------------------------------------------------------------- |
| id:                   | `"discountState"`                                                          |
| id example:           | `"discountState"`                                                          |
| partitionKey:         | `"customer:[customer_id]:discounts:[discount_uuid]:year:month"`            |
| partitionKey example: | `"customer:1061737:discounts:85679075-fe74-461e-9c22-808ac1393944:2024:4"` |

<details>

<summary>Example Item</summary>

```json
{
  "CurrentAmount": 400000000000,
  "Customer": {
    "AzureAccountId": "",
    "BillForPublicRepoUsage": false,
    "BillingTarget": 0,
    "CostCenterState": 0,
    "CostCenterUUID": "",
    "DiscountPlanName": "",
    "EffectiveAt": 0,
    "EnabledProducts": [],
    "EnterpriseCustomerId": "1061737",
    "HasPaymentMethod": false,
    "HasZuoraSubscription": false,
    "IsBillingLocked": false,
    "IsCostCenterProxy": false,
    "TradeScreening": {
      "FeaturesWithCommercialInteractionRestrictions": null,
      "HasAnyTradeRestrictions": false,
      "HasFullTradeRestrictions": false
    },
    "ZuoraAccountId": "",
    "ZuoraAccountNumber": "",
    "id": "customer",
    "partitionKey": "customer:1061737"
  },
  "IsFullyApplied": true,
  "TargetAmount": 400000000000,
  "Uuid": "85679075-fe74-461e-9c22-808ac1393944",
  "_attachments": "attachments/",
  "_etag": "\"5a00ceeb-0000-0100-0000-660d9c780000\"",
  "_rid": "5mFXAK7x5hp+uYMAAABoCw==",
  "_self": "dbs/5mFXAA==/colls/5mFXAK7x5ho=/docs/5mFXAK7x5hp+uYMAAABoCw==/",
  "_ts": 1712168056,
  "id": "discountState",
  "partitionKey": "customer:1061737:discounts:85679075-fe74-461e-9c22-808ac1393944:2024:4"
}

```

</details>

### Hourly Usage Discount Rollup

The id for these items matches the id of a corresponding usage item for the given time period. These items track the discount amount that has been applied to the corresponding usage with the same uuid as its id.

|                       |                                                |
| --------------------- | ---------------------------------------------- |
| id:                   | `"[uuid]"`                                     |
| id example:           | `"c7dc70ea-a835-50f1-a3db-e5ab3edb1cef"`       |
| partitionKey:         | `"[customer_id]:year:month:day:hour:discount"` |
| partitionKey example: | `"1061737:2024:4:1:15:discount"`              |

<details>

<summary>Example Item</summary>

```json

{
  "DiscountAmount": 24000000,
  "DiscountFor": null,
  "Pricing": {
    "AzureMeterId": "3dbfec75-284c-4c89-8c9c-0d395be81a0c",
    "EffectiveAt": 1689366600,
    "EffectiveDatePrices": [],
    "FreeForPublicRepos": true,
    "FriendlyName": "Actions Linux",
    "MeterType": 0,
    "Price": 8000000,
    "Product": "actions",
    "Sku": "actions_linux",
    "UnitType": 2,
    "id": "actions_linux",
    "partitionKey": "pricing"
  },
  "Quantity": 3000000000,
  "UsageAt": 1711987176523,
  "_attachments": "attachments/",
  "_etag": "\"e9000e15-0000-0100-0000-660ad9e90000\"",
  "_rid": "5mFXAK7x5hoVuYAAAABsDw==",
  "_self": "dbs/5mFXAA==/colls/5mFXAK7x5ho=/docs/5mFXAK7x5hoVuYAAAABsDw==/",
  "_ts": 1711987177,
  "id": "c7dc70ea-a835-50f1-a3db-e5ab3edb1cef",
  "partitionKey": "1061737:2024:4:1:15:discount"
}

```

</details>

### Hourly SKU Usage Discount Rollup

The id for these items matches the id of a corresponding SKU usage item for the given time period. These items track the discount amount that has been applied to the corresponding SKU usage with the same uuid as its id.

|                       |                                                         |
| --------------------- | ------------------------------------------------------- |
| id:                   | `"[uuid]"`                                              |
| id example:           | `"cb0f6929-3c60-56dd-8f52-d891d90472d6"`                |
| partitionKey:         | `"[customer_id]:[sku]:year:month:day:hour:discount"`    |
| partitionKey example: | `"1061737:actions_linux:2024:4:1:15:discount"` |

<details>

<summary>Example Item</summary>

```json
{
  "DiscountAmount": 8000000,
  "DiscountFor": null,
  "Pricing": {
    "AzureMeterId": "3dbfec75-284c-4c89-8c9c-0d395be81a0c",
    "EffectiveAt": 1689366600,
    "EffectiveDatePrices": [],
    "FreeForPublicRepos": true,
    "FriendlyName": "Actions Linux",
    "MeterType": 0,
    "Price": 8000000,
    "Product": "actions",
    "Sku": "actions_linux",
    "UnitType": 2,
    "id": "actions_linux",
    "partitionKey": "pricing"
  },
  "Quantity": 1000000000,
  "UsageAt": 1711983646266,
  "_attachments": "attachments/",
  "_etag": "\"5e007feb-0000-0100-0000-660acc1f0000\"",
  "_rid": "5mFXAK7x5hq7mYoAAAAYDQ==",
  "_self": "dbs/5mFXAA==/colls/5mFXAK7x5ho=/docs/5mFXAK7x5hq7mYoAAAAYDQ==/",
  "_ts": 1711983647,
  "id": "cb0f6929-3c60-56dd-8f52-d891d90472d6",
  "partitionKey": "1061737:actions_linux:2024:4:1:15:discount"
}
```

</details>

### Daily Usage Discount Rollup

Each item tracks the aggregate discounts applied to a customer's usage for a specific SKU in a one hour period. This partition will include items across different SKUs but each item will only represent the usage for a single SKU in the specified one hour period.

|                       |                                                              |
| --------------------- | ------------------------------------------------------------ |
| id:                   | `"[customer_id]:[sku]:[year]:[month]:[day]:[hour]:discount"` |
| id example:           | `"7464727:actions_macos_12_core:2023:7:25:13:discount"`      |
| partitionKey:         | `"[customer_id]:year:month:day:discount"`                    |
| partitionKey example: | `"7464727:2023:7:25:discount"`                               |

<details>

<summary>Example Item</summary>

```json

{
    "partitionKey": "1:2024:5:6:discount",
    "id": "1:actions_linux:2024:5:6:19:discount",
    "DiscountAmount": 40000000,
    "Quantity": 5000000000,
    "Pricing": {
        "partitionKey": "pricing",
        "id": "actions_linux",
        "Price": 8000000,
        "Product": "actions",
        "Sku": "actions_linux",
        "MeterType": 0,
        "FriendlyName": "Actions Linux",
        "AzureMeterId": "3dbfec75-284c-4c89-8c9c-0d395be81a0c",
        "EffectiveDatePrices": [],
        "FreeForPublicRepos": true,
        "EffectiveAt": 1689366600,
        "UnitType": 2
    },
    "UsageAt": 1715022262243,
    "DiscountFor": null,
    "_rid": "9xN8APCQWaGnAAAAAAAAAA==",
    "_self": "dbs/9xN8AA==/colls/9xN8APCQWaE=/docs/9xN8APCQWaGnAAAAAAAAAA==/",
    "_etag": "\"13006a5d-0000-0700-0000-663929b70000\"",
    "_attachments": "attachments/",
    "_ts": 1715022263
}

```

</details>

### Daily SKU Usage Discount Rollup

Each item tracks the aggregate discounts applied to customer's usage for a specific SKU in a one hour period. This partition will only contain items related to a single SKU.

|                       |                                                              |
| --------------------- | ------------------------------------------------------------ |
| id:                   | `"[customer_id]:[sku]:[year]:[month]:[day]:[hour]:discount"` |
| id example:           | `"1061737:actions_linux:2024:4:15:15:discount"`              |
| partitionKey:         | `"[customer_id]:[sku]:year:month:day:discount"`              |
| partitionKey example: | `"1061737:actions_linux:2024:4:15:discount"`         |

<details>

<summary>Example Item</summary>

```json

{
  "DiscountAmount": 312000000,
  "DiscountFor": null,
  "Pricing": {
    "AzureMeterId": "3dbfec75-284c-4c89-8c9c-0d395be81a0c",
    "EffectiveAt": 1689366600,
    "EffectiveDatePrices": [],
    "FreeForPublicRepos": true,
    "FriendlyName": "Actions Linux",
    "MeterType": 0,
    "Price": 8000000,
    "Product": "actions",
    "Sku": "actions_linux",
    "UnitType": 2,
    "id": "actions_linux",
    "partitionKey": "pricing"
  },
  "Quantity": 39000000000,
  "UsageAt": 1713193376120,
  "_attachments": "attachments/",
  "_etag": "\"c901d1a0-0000-0100-0000-661d4ef00000\"",
  "_rid": "5mFXAK7x5hpqk4gAAABwBQ==",
  "_self": "dbs/5mFXAA==/colls/5mFXAK7x5ho=/docs/5mFXAK7x5hpqk4gAAABwBQ==/",
  "_ts": 1713196784,
  "id": "1061737:actions_linux:2024:4:15:15:discount",
  "partitionKey": "1061737:actions_linux:2024:4:15:discount"
}

```

</details>

### Monthly Usage Discount Rollup

Each item tracks a customer's aggregate discount amount for the specified SKU in a one day period. This partition will contain items for all SKUs that a customer has discounts applied to for the given one month period.

|                       |                                                       |
| --------------------- | ----------------------------------------------------- |
| id:                   | `"[customer_id]:[sku]:[year]:[month]:[day]:discount"` |
| id example:           | `"7464727:actions_macos:2023:7:24:discount"`       |
| partitionKey:         | `"[customer_id]:year:month:discount"`                 |
| partitionKey example: | `"7464727:2023:7:discount"`                           |

<details>

<summary>Example Item</summary>

```json

{
  "DiscountAmount": 33056000000,
  "DiscountFor": null,
  "Pricing": {
    "AzureMeterId": "3dbfec75-284c-4c89-8c9c-0d395be81a0c",
    "EffectiveAt": 1689366600,
    "EffectiveDatePrices": [],
    "FreeForPublicRepos": true,
    "FriendlyName": "Actions Linux",
    "MeterType": 0,
    "Price": 8000000,
    "Product": "actions",
    "Sku": "actions_linux",
    "UnitType": 2,
    "id": "actions_linux",
    "partitionKey": "pricing"
  },
  "Quantity": 4132000000000,
  "UsageAt": 1713139207303,
  "_attachments": "attachments/",
  "_etag": "\"6e005ee0-0000-0100-0000-661dbf020000\"",
  "_rid": "5mFXAK7x5hrHoo8AAAAYCg==",
  "_self": "dbs/5mFXAA==/colls/5mFXAK7x5ho=/docs/5mFXAK7x5hrHoo8AAAAYCg==/",
  "_ts": 1713225474,
  "id": "1061737:actions_linux:2024:4:15:discount",
  "partitionKey": "1061737:2024:4:discount"
}

```

</details>

### Monthly SKU Usage Discount Rollup

Each item tracks the aggregate discount amount applied to the customer's usage for the specified SKU in a one day period. This partition will only contain items for the SKU specified in the partition key and there will be one item for each day the customer had discounts applied to the SKU.

|                       |                                                       |
| --------------------- | ----------------------------------------------------- |
| id:                   | `"[customer_id]:[sku]:[year]:[month]:[day]:discount"` |
| id example:           | `"1061737:actions_linux:2024:4:22:discount"`       |
| partitionKey:         | `"[customer_id]:[sku]:year:month:discount"`           |
| partitionKey example: | `"1061737:actions_linux:2024:4:discount"`     |

<details>

<summary>Example Item</summary>

```json

{
  "DiscountAmount": 29328000000,
  "DiscountFor": null,
  "Pricing": {
    "AzureMeterId": "3dbfec75-284c-4c89-8c9c-0d395be81a0c",
    "EffectiveAt": 1689366600,
    "EffectiveDatePrices": [],
    "FreeForPublicRepos": true,
    "FriendlyName": "Actions Linux",
    "MeterType": 0,
    "Price": 8000000,
    "Product": "actions",
    "Sku": "actions_linux",
    "UnitType": 2,
    "id": "actions_linux",
    "partitionKey": "pricing"
  },
  "Quantity": 3666000000000,
  "UsageAt": 1713744012393,
  "_attachments": "attachments/",
  "_etag": "\"6205388b-0000-0100-0000-6626f9190000\"",
  "_rid": "5mFXAK7x5hpIy5MAAACcAA==",
  "_self": "dbs/5mFXAA==/colls/5mFXAK7x5ho=/docs/5mFXAK7x5hpIy5MAAACcAA==/",
  "_ts": 1713830169,
  "id": "1061737:actions_linux:2024:4:22:discount",
  "partitionKey": "1061737:actions_linux:2024:4:discount"
}

```

</details>

</details>

## Invoices

<details>

<summary>Expand</summary>

### Customer Invoices

Provides a summary of all of the usage a customer was invoiced for in a given month.

|                       |                                                    |
| --------------------- | -------------------------------------------------- |
| id:                   | `"customer:[customer_id]:invoices:[year]:[month]"` |
| id example:           | `"customer:1061737:invoices:2023:6"`               |
| partitionKey:         | `"customer:[customer_id]:invoices"`                |
| partitionKey example: | `"customer:1061737:invoices"`                      |

<details>

<summary>Example Item</summary>

Note: some BillingItems were removed to condense this example for these docs.

```json
[{
  "CustomerId": "9576408",
  "Month": 3,
  "Period": "monthly",
  "ProductTotals": {
    "git_lfs": {
      "Product": "git_lfs",
      "SkuTotals": {
        "git_lfs_storage": {
          "BillingItems": [
            {
              "AppliedCostPerQuantity": 94086,
              "BilledAmount": 783013560,
              "EntityDetail": {
                "CostCenterDetail": {
                  "CostCenterState": 0,
                  "CostCenterUUID": "",
                  "EnterpriseCustomerId": "9576408",
                  "IsCostCenterProxy": false
                },
                "CustomerId": "9576408",
                "OrganizationId": 146325715,
                "RepositoryId": 697659100
              },
              "FractionalQuantity": 0,
              "FullQuantity": 8322317736600,
              "Pricing": {
                "AzureMeterId": "bf8ec46b-9900-5280-9cd4-45e65b3de557",
                "EffectiveAt": 1692727200,
                "EffectiveDatePrices": [],
                "FreeForPublicRepos": false,
                "FriendlyName": "Git LFS storage",
                "MeterType": 1,
                "Price": 94086,
                "Product": "git_lfs",
                "Sku": "git_lfs_storage",
                "UnitType": 9,
                "id": "git_lfs_storage",
                "partitionKey": "pricing"
              },
              "Quantity": 8322317736600,
              "SourceUri": "InternallyProcessedEvent",
              "UsageAt": 1709251200000,
              "id": "9576408:git_lfs_storage:2024:3:1",
              "partitionKey": "9576408:2024:3"
            },
            {
              "AppliedCostPerQuantity": 94086,
              "BilledAmount": 783013560,
              "EntityDetail": {
                "CostCenterDetail": {
                  "CostCenterState": 0,
                  "CostCenterUUID": "",
                  "EnterpriseCustomerId": "9576408",
                  "IsCostCenterProxy": false
                },
                "CustomerId": "9576408",
                "OrganizationId": 146325715,
                "RepositoryId": 698279585
              },
              "FractionalQuantity": 0,
              "FullQuantity": 8322317736600,
              "Pricing": {
                "AzureMeterId": "bf8ec46b-9900-5280-9cd4-45e65b3de557",
                "EffectiveAt": 1692727200,
                "EffectiveDatePrices": [],
                "FreeForPublicRepos": false,
                "FriendlyName": "Git LFS storage",
                "MeterType": 1,
                "Price": 94086,
                "Product": "git_lfs",
                "Sku": "git_lfs_storage",
                "UnitType": 9,
                "id": "git_lfs_storage",
                "partitionKey": "pricing"
              },
              "Quantity": 8322317736600,
              "SourceUri": "InternallyProcessedEvent",
              "UsageAt": 1709337600000,
              "id": "9576408:git_lfs_storage:2024:3:2",
              "partitionKey": "9576408:2024:3"
            }
          ],
          "Sku": "git_lfs_storage",
          "UsageTotal": {
            "Discount": 22.476399405,
            "Gross": 24.27342036,
            "Net": 1.797020955,
            "Quantity": 257991.8498346
          }
        }
      },
      "UsageTotal": {
        "Discount": 22.476399405,
        "Gross": 24.27342036,
        "Net": 1.797020955,
        "Quantity": 257991.8498346
      }
    }
  },
  "State": "submitted",
  "UsageTotal": {
    "Discount": 22.476399405,
    "Gross": 24.27342036,
    "Net": 1.797020955,
    "Quantity": 257991.8498346
  },
  "Uuid": "",
  "Year": 2024,
  "_attachments": "attachments/",
  "_etag": "\"11003da1-0000-0100-0000-660a07120000\"",
  "_rid": "5mFXAK7x5hoHwXkAAADgCA==",
  "_self": "dbs/5mFXAA==/colls/5mFXAK7x5ho=/docs/5mFXAK7x5hoHwXkAAADgCA==/",
  "_ts": 1711933202,
  "id": "customer:9576408:invoices:2024:3",
  "partitionKey": "customer:9576408:invoices"
}]
```

</details>

### Active Invoices

Each item represents a Zuora customer invoice that will be processed for the current month. See our [emission docs](https://github.com/github/billing-platform/blob/main/docs/emission/zuora-emission.md#cosmos-queries) for more details.

|                       |                                                    |
| --------------------- | -------------------------------------------------- |
| id:                   | `"customer:[customer_id]:invoices:[year]:[month]"` |
| id example:           | `"customer:5169203:invoices:2023:7"`               |
| partitionKey:         | `"invoices:active:[year]:[month]"`                 |
| partitionKey example: | `"invoices:active:2023:7"`                         |

### Submitted Invoices

These records are created when a customer's invoice is successfully submitted to Zuora.

|                       |                                                    |
| --------------------- | -------------------------------------------------- |
| id:                   | `"customer:[customer_id]:invoices:[year]:[month]"` |
| id example:           | `"customer:5169203:invoices:2023:7"`               |
| partitionKey:         | `"invoices:submitted:[year]:[month]"`              |
| partitionKey example: | `"invoices:submitted:2023:7"`                      |

<details>

<summary>Example Item</summary>

```json

{
  "SubmittedAt": "2024-05-01T01:10:03.315628018Z",
  "_attachments": "attachments/",
  "_etag": "\"3b0119dd-0000-0100-0000-6631966c0000\"",
  "_rid": "5mFXAK7x5hpFcZQAAADcDg==",
  "_self": "dbs/5mFXAA==/colls/5mFXAK7x5ho=/docs/5mFXAK7x5hpFcZQAAADcDg==/",
  "_ts": 1714525804,
  "id": "customer:9576408:invoices:2024:4",
  "partitionKey": "invoices:submitted:2024:4"
}

```

</details>

### Rejected Invoices

These items are created when an invoice is rejected by Zuora.

|                       |                                                    |
| --------------------- | -------------------------------------------------- |
| id:                   | `"customer:[customer_id]:invoices:[year]:[month]"` |
| id example:           | `"customer:5169203:invoices:2023:7"`               |
| partitionKey:         | `"invoices:rejected:[year]:[month]"`               |
| partitionKey example: | `"invoices:rejected:2023:7"`                       |

### Confirmed Invoices

|                       |                                                    |
| --------------------- | -------------------------------------------------- |
| id:                   | `"customer:[customer_id]:invoices:[year]:[month]"` |
| id example:           | `"customer:5169203:invoices:2023:7"`               |
| partitionKey:         | `"invoices:confirmed:[year]:[month]"`              |
| partitionKey example: | `"invoices:confirmed:2023:7"`                      |

</details>

## Products

<details>

<summary>Expand</summary>

|                       |                    |
| --------------------- | ------------------ |
| id:                   | `"[product_name]"` |
| id example:           | `"actions"`        |
| partitionKey:         | `"product"`        |
| partitionKey example: | `"product"`        |

<details>

<summary>Example Item</summary>

```json

{
  "FriendlyProductName": "Actions",
  "Name": "actions",
  "ZuoraUsageIdentifier": "GitHub Actions Usage",
  "_attachments": "attachments/",
  "_etag": "\"29024847-0000-0100-0000-6557a1c10000\"",
  "_rid": "5mFXAK7x5hpyAQAAAAC0CQ==",
  "_self": "dbs/5mFXAA==/colls/5mFXAK7x5ho=/docs/5mFXAK7x5hpyAQAAAAC0CQ==/",
  "_ts": 1700241857,
  "id": "actions",
  "partitionKey": "product"
}

```

</details>

</details>

## Repositories

<details>

<summary>Expand</summary>

In order to know if usage is eligible for a public repo discount, we store some basic information about repos in billing platform.

|                       |               |
| --------------------- | ------------- |
| id:                   | `"[repoID]"`      |
| id example:           | `"405878266"` |
| partitionKey:         | `"repo:[repoID]"`     |
| partitionKey example: | `"repo:405878266"`     |

<details>

<summary>Example Item</summary>

```json

{
  "IsPublic": false,
  "RepoId": 751591874,
  "_attachments": "attachments/",
  "_etag": "\"23004b98-0000-0100-0000-65bc22d20000\"",
  "_rid": "5mFXAK7x5hrPHLIAAAC4CQ==",
  "_self": "dbs/5mFXAA==/colls/5mFXAK7x5ho=/docs/5mFXAK7x5hrPHLIAAAC4CQ==/",
  "_ts": 1706828498,
  "id": "751591874",
  "partitionKey": "repo:751591874"
}

```

</details>

</details>

## Top Org Repo

<details>

<summary>Expand</summary>

The following two partitions are used when identifying what the top organizations / repositories are for a customer.

## TopOrgs

|                       |               |
| --------------------- | ------------- |
| id:                   | `"topOrgs"`      |
| partitionKey:         | `"[customerOrCostCenterId]:[usageTime]:topOrgs"`     |
| partitionKey example: | `"1061737:2024:8:topOrgs"`     |

<details>

<summary>Example Item</summary>

```json

{
    "partitionKey": "1:2024:topOrgs",
    "id": "topOrgs",
    "resourceIds": [
        1,
        2,
        3,
        4,
        5,
    ],
    "_rid": "s5A0AOI8-Xj1BwAAAAAAAA==",
    "_self": "dbs/s5A0AA==/colls/s5A0AOI8-Xg=/docs/s5A0AOI8-Xj1BwAAAAAAAA==/",
    "_etag": "\"a003ce0c-0000-0700-0000-66ccdc400000\"",
    "_attachments": "attachments/",
    "_ts": 1724701760
}

```

</details>

## TopRepos

|                       |               |
| --------------------- | ------------- |
| id:                   | `"topRepos"`      |
| partitionKey:         | `"[customerOrCostCenterId]:[usageTime]:topRepos"`     |
| partitionKey example: | `"1061737:2024:8:topRepos"`     |

<details>

<summary>Example Item</summary>

```json

{
    "partitionKey": "1:2024:topRepos",
    "id": "topRepos",
    "resourceIds": [
        1,
        2,
        3,
        4,
        5,
    ],
    "_rid": "s5A0AOI8-Xj1BwAAAAAAAA==",
    "_self": "dbs/s5A0AA==/colls/s5A0AOI8-Xg=/docs/s5A0AOI8-Xj1BwAAAAAAAA==/",
    "_etag": "\"a003ce0c-0000-0700-0000-66ccdc400000\"",
    "_attachments": "attachments/",
    "_ts": 1724701760
}

```

</details>

</details>

## Usage

<details>

<summary>Expand</summary>

_Note that almost all usage partitions have a rollup for hourly, daily and monthly usage totals. For the purpose of these docs, we have only included select examples for time period usage partitions but for example, SKU and repo usage partitions will also have year, month, day and hour variations_

### Usage (Monthly)

Each item represents an aggregate total of the customer's usage of a specific SKU during a one month period. This partition will contain items for different SKUs but each item will only contain data for the SKU specified in its id.

|                       |                                                |
| --------------------- | ---------------------------------------------- |
| id:                   | `"[customer_id]:[product_sku]:[year]:[month]"` |
| id example:           | `"1061737:actions_linux_16_core:2023:6"`       |
| partitionKey:         | `"[customer_id]:[year]"`                       |
| partitionKey example: | `"1061737:2023"`                               |

<details>

<summary>Example Item</summary>

```json

{
  "AppliedCostPerQuantity": 8000000,
  "BilledAmount": 3172392000000,
  "EntityDetail": {
    "CostCenterDetail": {
      "CostCenterState": 0,
      "CostCenterUUID": "",
      "EnterpriseCustomerId": "1061737",
      "IsCostCenterProxy": false
    },
    "CustomerId": "1061737",
  },
  "FractionalQuantity": 0,
  "FullQuantity": 396549000000000,
  "Pricing": {
    "AzureMeterId": "3dbfec75-284c-4c89-8c9c-0d395be81a0c",
    "EffectiveAt": 1689366600,
    "EffectiveDatePrices": [],
    "FreeForPublicRepos": true,
    "FriendlyName": "Actions Linux",
    "MeterType": 0,
    "Price": 8000000,
    "Product": "actions",
    "Sku": "actions_linux",
    "UnitType": 2,
    "id": "actions_linux",
    "partitionKey": "pricing"
  },
  "Quantity": 396549000000000,
  "UsageAt": 1711929617926,
  "_attachments": "attachments/",
  "_etag": "\"49012800-0000-0100-0000-663185e60000\"",
  "_rid": "5mFXAK7x5hoxyHsAAACYAw==",
  "_self": "dbs/5mFXAA==/colls/5mFXAK7x5ho=/docs/5mFXAK7x5hoxyHsAAACYAw==/",
  "_ts": 1714521574,
  "id": "1061737:actions_linux:2024:4",
  "partitionKey": "1061737:2024"
}

```

</details>

### Usage (Daily)

Each item represents an aggregate total of the customer's usage of a specific SKU during a one day period. This partition will contain items for different SKUs but a single item will only contain data for the SKU specified in its id.

|                       |                                                      |
| --------------------- | ---------------------------------------------------- |
| id:                   | `"[customer_id]:[product_sku]:[year]:[month]:[day]"` |
| id example:           | `"1061737:actions_linux_16_core:2023:6:28"`          |
| partitionKey:         | `"[customer_id]:[year]:[month]"`                     |
| partitionKey example: | `"1061737:2023:6"`                                   |

<details>

<summary>Example Item</summary>

```json

{
  "AppliedCostPerQuantity": 8000000,
  "BilledAmount": 80088000000,
  "EntityDetail": {
    "CostCenterDetail": {
      "CostCenterState": 0,
      "CostCenterUUID": "",
      "EnterpriseCustomerId": "1061737",
      "IsCostCenterProxy": false
    },
    "CustomerId": "1061737"
  },
  "FractionalQuantity": 0,
  "FullQuantity": 10011000000000,
  "Pricing": {
    "AzureMeterId": "3dbfec75-284c-4c89-8c9c-0d395be81a0c",
    "EffectiveAt": 1689366600,
    "EffectiveDatePrices": [],
    "FreeForPublicRepos": true,
    "FriendlyName": "Actions Linux",
    "MeterType": 0,
    "Price": 8000000,
    "Product": "actions",
    "Sku": "actions_linux",
    "UnitType": 2,
    "id": "actions_linux",
    "partitionKey": "pricing"
  },
  "Quantity": 10011000000000,
  "UsageAt": 1713744012393,
  "_attachments": "attachments/",
  "_etag": "\"8d00745f-0000-0100-0000-6626f9690000\"",
  "_rid": "5mFXAK7x5hrmHI0AAADcDQ==",
  "_self": "dbs/5mFXAA==/colls/5mFXAK7x5ho=/docs/5mFXAK7x5hrmHI0AAADcDQ==/",
  "_ts": 1713830249,
  "id": "1061737:actions_linux:2024:4:22",
  "partitionKey": "1061737:2024:4"
}

```

</details>

### Usage (Hourly)

> [!NOTE]
> Hourly usage is no longer written for this partition. The only partition that has hourly usage at the time of writing is the `byOrgRepoProductSku` partition.

Each item represents an aggregate total of a customer's usage for a SKU in a given one hour period.

|                       |                                                             |
| --------------------- | ----------------------------------------------------------- |
| id:                   | `"[customer_id]:[product_sku]:[year]:[month]:[day]:[hour]"` |
| id example:           | `"1061737:actions_linux_16_core:2023:6:30:13"`              |
| partitionKey:         | `"[customer_id]:[year]:[month]:[day]"`                      |
| partitionKey example: | `"1061737:2023:6:28"`                                       |

<details>

<summary>Example Item</summary>

```json

{
  "AppliedCostPerQuantity": 8000000,
  "BilledAmount": 2480000000,
  "EntityDetail": {
    "CostCenterDetail": {
      "CostCenterState": 0,
      "CostCenterUUID": "",
      "EnterpriseCustomerId": "1061737",
      "IsCostCenterProxy": false
    },
    "CustomerId": "1061737"
  },
  "FractionalQuantity": 0,
  "FullQuantity": 310000000000,
  "Pricing": {
    "AzureMeterId": "3dbfec75-284c-4c89-8c9c-0d395be81a0c",
    "EffectiveAt": 1689366600,
    "EffectiveDatePrices": [],
    "FreeForPublicRepos": true,
    "FriendlyName": "Actions Linux",
    "MeterType": 0,
    "Price": 8000000,
    "Product": "actions",
    "Sku": "actions_linux",
    "UnitType": 2,
    "id": "actions_linux",
    "partitionKey": "pricing"
  },
  "Quantity": 310000000000,
  "UsageAt": 1713823242696,
  "_attachments": "attachments/",
  "_etag": "\"330006bb-0000-0100-0000-6626ebe70000\"",
  "_rid": "5mFXAK7x5hrXsYwAAACUBw==",
  "_self": "dbs/5mFXAA==/colls/5mFXAK7x5ho=/docs/5mFXAK7x5hrXsYwAAACUBw==/",
  "_ts": 1713826791,
  "id": "1061737:actions_linux:2024:4:22:22",
  "partitionKey": "1061737:2024:4:22"
}

```

</details>

### Usage (Minute)

|                       |                                                                  |
| --------------------- | ---------------------------------------------------------------- |
| id:                   | `"[customer_id]:[year]:[month]:[day]:[hour]"`                    |
| id example:           | `"1061737:2023:7:25:0"`                                          |
| partitionKey:         | `"[customer_id]:[org_id]:[repo_id]:[year]:[month]:[day]:[hour]"` |
| partitionKey example: | `"1061737:110058594:536624603:2023:7:25:0"`                      |

#### Other usage partitions

---

### Usage SKU (Daily)

Each item represents an aggregate total of a customer's total usage for a specific SKU in a one day period. This partition will only contain items for the single SKU in the partition key and there will be one item for each day in which the customer has usage for the SKU.

|                       |                                                      |
| --------------------- | ---------------------------------------------------- |
| id:                   | `"[customer_id]:[product_sku]:[year]:[month]:[day]"` |
| id example:           | `"1061737:actions_linux_16_core:2023:6:28"`          |
| partitionKey:         | `"[customer_id]:[product_sku]:[year]:[month]"`       |
| partitionKey example: | `"1061737:actions_linux_16_core:2023:6"`             |

<details>

<summary>Example Item</summary>

```json

{
  "AppliedCostPerQuantity": 8000000,
  "BilledAmount": 80088000000,
  "EntityDetail": {
    "CostCenterDetail": {
      "CostCenterState": 0,
      "CostCenterUUID": "",
      "EnterpriseCustomerId": "1061737",
      "IsCostCenterProxy": false
    },
    "CustomerId": "1061737"
  },
  "FractionalQuantity": 0,
  "FullQuantity": 10011000000000,
  "Pricing": {
    "AzureMeterId": "3dbfec75-284c-4c89-8c9c-0d395be81a0c",
    "EffectiveAt": 1689366600,
    "EffectiveDatePrices": [],
    "FreeForPublicRepos": true,
    "FriendlyName": "Actions Linux",
    "MeterType": 0,
    "Price": 8000000,
    "Product": "actions",
    "Sku": "actions_linux",
    "UnitType": 2,
    "id": "actions_linux",
    "partitionKey": "pricing"
  },
  "Quantity": 10011000000000,
  "UsageAt": 1713744012393,
  "_attachments": "attachments/",
  "_etag": "\"82001688-0000-0100-0000-6626f9690000\"",
  "_rid": "5mFXAK7x5hphWIoAAAA6Ag==",
  "_self": "dbs/5mFXAA==/colls/5mFXAK7x5ho=/docs/5mFXAK7x5hphWIoAAAA6Ag==/",
  "_ts": 1713830249,
  "id": "1061737:actions_linux:2024:4:22",
  "partitionKey": "1061737:actions_linux:2024:4"
}

```

</details>

### Usage SKU (Minute)

|                       |                                                             |
| --------------------- | ----------------------------------------------------------- |
| id:                   | `"[uuid]"`                                                  |
| id example:           | `"ee5e1312-8bb1-48ed-8923-f8012921edea"`                    |
| partitionKey:         | `"[customer_id]:[product_sku]:[year]:[month]:[day]:[hour]"` |
| partitionKey example: | `"1061737:actions_linux_16_core:2023:6:28:13"`              |

<details>

<summary>Example Item</summary>

```json

{
  "AppliedCostPerQuantity": 8000000,
  "BilledAmount": 8000000,
  "EntityDetail": {
    "ActorId": 1377042,
    "CostCenterDetail": {
      "CostCenterState": 0,
      "CostCenterUUID": "",
      "EnterpriseCustomerId": "1061737",
      "IsCostCenterProxy": false
    },
    "CustomerId": "1061737",
    "OrganizationId": 30846345,
    "RepositoryId": 399950932
  },
  "FractionalQuantity": 0,
  "FullQuantity": 1000000000,
  "Pricing": {
    "AzureMeterId": "3dbfec75-284c-4c89-8c9c-0d395be81a0c",
    "EffectiveAt": 1689366600,
    "EffectiveDatePrices": [],
    "FreeForPublicRepos": true,
    "FriendlyName": "Actions Linux",
    "MeterType": 0,
    "Price": 8000000,
    "Product": "actions",
    "Sku": "actions_linux",
    "UnitType": 2,
    "id": "actions_linux",
    "partitionKey": "pricing"
  },
  "Quantity": 1000000000,
  "SourceUri": "gid://git-hub/CheckRun/24125764879",
  "UsageAt": 1713823242696,
  "_attachments": "attachments/",
  "_etag": "\"e2040aae-0000-0100-0000-6626de0b0000\"",
  "_rid": "5mFXAK7x5hoaUJAAAABkDA==",
  "_self": "dbs/5mFXAA==/colls/5mFXAK7x5ho=/docs/5mFXAK7x5hoaUJAAAABkDA==/",
  "_ts": 1713823243,
  "id": "65fc3f21-969b-58b0-b67d-1a8ab534eba0",
  "partitionKey": "1061737:actions_linux:2024:4:22:22"
}

```

</details>

### Usage Repo (Daily)

Each item represents an aggregate total of a customer's usage for the repo for each SKU for a one day period.

|                       |                                                              |
| --------------------- | ------------------------------------------------------------ |
| id:                   | `"[customer_id]:[sku]:[year]:[month]:[day]"`                 |
| id example:           | `"1061737:actions_linux:2023:7:11"`                          |
| partitionKey:         | `"[customer_id]:repo:[repo_id]:[year]:[month]:byProductSku"` |
| partitionKey example: | `"1061737:repo:702449570:2023:7:byProductSku"`               |

<details>

<summary>Example Item</summary>

```json

{
  "partitionKey": "1061737:repo:702449570:2024:8:byProductSku",
  "id": "1061737:codespaces_prebuild_storage:2024:8:1",
  "BilledAmount": 38951568,
  "FullQuantity": 556451568,
  "Quantity": 556451568,
  "AppliedCostPerQuantity": 70000000,
  "FractionalQuantity": 0,
  "Pricing": {
    "partitionKey": "pricing",
    "id": "codespaces_prebuild_storage",
    "Price": 70000000,
    "Product": "codespaces",
    "Sku": "codespaces_prebuild_storage",
    "MeterType": 0,
    "FriendlyName": "Codespaces prebuild storage",
    "AzureMeterId": "4efa15aa-3748-5fca-8310-70a2f7b9e3f4",
    "EffectiveDatePrices": null,
    "FreeForPublicRepos": false,
    "EffectiveAt": 1709168400,
    "UnitType": 9
  },
  "EntityDetail": {
    "CustomerId": "1061737",
    "OrganizationId": 115224552,
    "RepositoryId": 702449570,
    "CostCenterDetail": {
      "EnterpriseCustomerId": "1061737",
      "CostCenterUUID": "",
      "IsCostCenterProxy": false,
      "CostCenterState": 0
    }
  },
  "SourceUri": "gid:\/\/git-hub\/Command\/codespaces\/billing\/dispatch_message\/event_id\/287b8e8d-e83e-4c05-849b-efcdca66608e",
  "UsageAt": 1722470400000,
  "_rid": "5mFXAK7x5hpLbs0AAADlCg==",
  "_self": "dbs\/5mFXAA==\/colls\/5mFXAK7x5ho=\/docs\/5mFXAK7x5hpLbs0AAADlCg==\/",
  "_etag": "\"e7023c03-0000-0100-0000-66ac15d30000\"",
  "_attachments": "attachments\/",
  "_ts": 1722553811
}

```

</details>

### Usage Org (Daily)

Each item represents an aggregate total of a customer's usage for the org for each SKU for a one day period.

|                       |                                                            |
| --------------------- | ---------------------------------------------------------- |
| id:                   | `"[customer_id]:[sku]:[year]:[month]:[day]"`               |
| id example:           | `"1061737:actions_linux:2024:8:1"`                       |
| partitionKey:         | `"[customer_id]:org:[org_id]:[year]:[month]:byProductSku"` |
| partitionKey example: | `"1061737:org:115224552:2024:8:byProductSku"`              |

<details>

<summary>Example Item</summary>

```json

{
  "partitionKey": "1061737:org:115224552:2024:8:byProductSku",
  "id": "1061737:actions_storage:2024:8:1",
  "BilledAmount": 2544,
  "FullQuantity": 7590864,
  "Quantity": 7590864,
  "AppliedCostPerQuantity": 336020,
  "FractionalQuantity": 0,
  "Pricing": {
    "partitionKey": "pricing",
    "id": "actions_storage",
    "Price": 336020,
    "Product": "actions",
    "Sku": "actions_storage",
    "MeterType": 1,
    "FriendlyName": "Actions storage",
    "AzureMeterId": "832bfa96-c7db-416b-aa5b-6ea89054d493",
    "EffectiveDatePrices": null,
    "FreeForPublicRepos": true,
    "EffectiveAt": 1689366600,
    "UnitType": 9
  },
  "EntityDetail": {
    "CustomerId": "1061737",
    "OrganizationId": 115224552,
    "RepositoryId": 762242622,
    "CostCenterDetail": {
      "EnterpriseCustomerId": "1061737",
      "CostCenterUUID": "",
      "IsCostCenterProxy": false,
      "CostCenterState": 0
    }
  },
  "SourceUri": "InternallyProcessedEvent",
  "UsageAt": 1722470400000,
  "_rid": "5mFXAK7x5hodOcAAAABpBw==",
  "_self": "dbs\/5mFXAA==\/colls\/5mFXAK7x5ho=\/docs\/5mFXAK7x5hodOcAAAABpBw==\/",
  "_etag": "\"3f06b92a-0000-0100-0000-66ac14c90000\"",
  "_attachments": "attachments\/",
  "_ts": 1722553545
}

```

</details>

### Usage By Org/Repo (Daily)

Each item represents a customer's aggregate usage across all SKUS for one repo during a one day period.

|                       |                                                       |
| --------------------- | ----------------------------------------------------- |
| id:                   | `"[customer_id]:repo:[repo_id]:[year]:[month]:[day]"` |
| id example:           | `"1061737:repo:494096553:2023:7:22"`                  |
| partitionKey:         | `"[customer_id]:[year]:[month]:byOrgAndRepo"`         |
| partitionKey example: | `"1061737:2023:7:byOrgAndRepo"`                       |

<details>

<summary>Example Item</summary>

```json

{
  "AppliedCostPerQuantity": 94086,
  "BilledAmount": 2412120,
  "EntityDetail": {
    "CostCenterDetail": {
      "CostCenterState": 0,
      "CostCenterUUID": "",
      "EnterpriseCustomerId": "1061737",
      "IsCostCenterProxy": false
    },
    "CustomerId": "1061737",
    "OrganizationId": 132485584,
    "RepositoryId": 751591874
  },
  "FractionalQuantity": 0,
  "FullQuantity": 25637447832,
  "Quantity": 25637447832,
  "UsageAt": 1713744000000,
  "_attachments": "attachments/",
  "_etag": "\"9602baaf-0000-0100-0000-6626ebf70000\"",
  "_rid": "5mFXAK7x5hph-JcAAAACCQ==",
  "_self": "dbs/5mFXAA==/colls/5mFXAK7x5ho=/docs/5mFXAK7x5hph-JcAAAACCQ==/",
  "_ts": 1713826807,
  "id": "1061737:repo:751591874:2024:4:22",
  "partitionKey": "1061737:2024:4:byOrgAndRepo"
}

```

</details>

### Usage By Org/Repo/Product/SKU (Daily)

Each item represents a customer's usage for a single SKU for one repo during a one day period.

|                       |                                                                                             |
| --------------------- | ------------------------------------------------------------------------------------------- |
| id:                   | `"customer:[customer_id]:org:[org_id]:repo:[repo_id]:product:[product]:sku:[sku]:[time]"`   |
| id example:           | `"customer:1061737:org:93409011:repo:654673064:product:actions:sku:actions_linux:2023:7:1"` |
| partitionKey:         | `"[customer_id]:[year]:[month]:byOrgRepoProductSku"`                                        |
| partitionKey example: | `"1061737:2023:7:byOrgRepoProductSku"`                                                      |

<details>

<summary>Example Item</summary>

```json
{
        "partitionKey": "1:2024:5:byOrgRepoProductSku",
        "id": "customer:1:org:4:repo:1:product:actions:sku:actions_linux:2024:5:6",
        "BilledAmount": 80000000,
        "FullQuantity": 10000000000,
        "Quantity": 10000000000,
        "AppliedCostPerQuantity": 8000000,
        "FractionalQuantity": 0,
        "Pricing": {
            "partitionKey": "pricing",
            "id": "actions_linux",
            "Price": 8000000,
            "Product": "actions",
            "Sku": "actions_linux",
            "MeterType": 0,
            "FriendlyName": "Actions Linux",
            "AzureMeterId": "3dbfec75-284c-4c89-8c9c-0d395be81a0c",
            "EffectiveDatePrices": [],
            "FreeForPublicRepos": true,
            "EffectiveAt": 1689366600,
            "UnitType": 2
        },
        "EntityDetail": {
            "CustomerId": "1",
            "OrganizationId": 4,
            "RepositoryId": 1,
            "ActorId": 2,
            "CostCenterDetail": {
                "EnterpriseCustomerId": "1",
                "CostCenterUUID": "",
                "IsCostCenterProxy": false,
                "CostCenterState": 0
            }
        },
        "SourceUri": "git://run/id",
        "UsageAt": 1715015858117,
        "_rid": "9xN8APCQWaEpAAAAAAAAAA==",
        "_self": "dbs/9xN8AA==/colls/9xN8APCQWaE=/docs/9xN8APCQWaEpAAAAAAAAAA==/",
        "_etag": "\"1300655d-0000-0700-0000-663929b70000\"",
        "_attachments": "attachments/",
        "_ts": 1715022263
    },


```

</details>

</details>


## Usage Reports

<details>

<summary>Expand</summary>

### Active Usage Report Exports (loading and pending)

|                       |                                                       |
| --------------------- | ----------------------------------------------------- |
| id:                   | `"customer:[customerId]:actor:[actorId]"` |
| id example:           | `"customer:1061737:actor:108798"`                  |
| partitionKey:         | `"usageReportExports:active"`         |

<details>

<summary>Example document</summary>

```json
{
    "partitionKey": "usageReportExports:active",
    "id": "customer:1061737:actor:108798",
    "CustomerID": "1061737",
    "ActorID": 108798,
    "StartDate": "2023-11-06T19:56:00Z",
    "EndDate": "2024-05-03T18:56:02Z",
    "Status": "pending",
    "_rid": "X5YCAN1hDDyHAAAAAAAAAA==",
    "_self": "dbs/X5YCAA==/colls/X5YCAN1hDDw=/docs/X5YCAN1hDDyHAAAAAAAAAA==/",
    "_etag": "\"0000f100-0000-0700-0000-663e31670000\"",
    "_attachments": "attachments/",
    "_ts": 1715351911
}
```

</details>

### Usage Report Exports Completed

|                       |                                                       |
| --------------------- | ----------------------------------------------------- |
| id:                   | `"[uuid]"` |
| id example:           | `"0f5e4e5f-8c8e-46e7-870f-581fc737590f"`                  |
| partitionKey:         | `"customer:[customerID]:usageReportExports:completed"`         |
| partitionKey example: | `"customer:1061737:usageReportExports:completed"`  |

<details>

<summary>Example document</summary>

```json
{
    "partitionKey": "customer:1061737:usageReportExports:completed",
    "id": "3d48883e-a2a7-412b-a283-9f03d08ec321",
    "CustomerID": "1061737",
    "ActorID": 108798,
    "StartDate": "2023-11-06T19:56:00Z",
    "EndDate": "2024-05-03T18:56:02Z",
    "Status": "completed",
    "ExportOperationUUID": "869c2d7e-8280-4e03-a4f2-89660d135aa5",
    "ExportBlobs": [
        "https://mbnonprod.blob.core.windows.net/billing-metered-exports-reports/usageReport_1_48527877aebd4972a96676998096633b.csv"
    ],
    "_rid": "X5YCAN1hDDyHAAAAAAAAAA==",
    "_self": "dbs/X5YCAA==/colls/X5YCAN1hDDw=/docs/X5YCAN1hDDyHAAAAAAAAAA==/",
    "_etag": "\"0000f100-0000-0700-0000-663e31670000\"",
    "_attachments": "attachments/",
    "_ts": 1715351911
}
```

</details>

### Usage Report Exports Failed

|                       |                                                       |
| --------------------- | ----------------------------------------------------- |
| id:                   | `"[uuid]"` |
| id example:           | `"0f5e4e5f-8c8e-46e7-870f-581fc737590f"`                  |
| partitionKey:         | `"customer:[customerID]:usageReportExports:failed"`         |
| partitionKey example: | `"customer:1061737:usageReportExports:failed"`  |


<details>

<summary>Example document</summary>

```json
{
    "partitionKey": "customer:1061737:usageReportExports:failed",
    "id": "c7dbe578-d078-4af5-baf7-0ac9d05a69d7",
    "CustomerID": "1061737",
    "ActorID": 108798,
    "StartDate": "2023-11-06T19:56:00Z",
    "EndDate": "2024-05-03T18:56:02Z",
    "Status": "failed",
    "ExportOperationUUID": "cbdf0a62-9dbc-4a6d-9b1a-7032c7790505",
    "_rid": "X5YCAN1hDDx9AAAAAAAAAA==",
    "_self": "dbs/X5YCAA==/colls/X5YCAN1hDDw=/docs/X5YCAN1hDDx9AAAAAAAAAA==/",
    "_etag": "\"0000e600-0000-0700-0000-663e2fbe0000\"",
    "_attachments": "attachments/",
    "_ts": 1715351486
}
```

</details>

</details>

## Watermark

<details>

<summary>Expand</summary>

## Active Events

|                       |                                   |
| --------------------- | --------------------------------- |
| id:                   | `"[event_id]"`                    |
| id example:           | `"9629029"`                       |
| partitionKey:         | `"active:[product_sku]:events"`   |
| partitionKey example: | `"active:actions_storage:events"` |

### Customer Events

|                       |                                                       |
| --------------------- | ----------------------------------------------------- |
| id:                   | `"[uuid]"`                                            |
| id example:           | `"720e7d11-45fe-55f5-b57f-5bd0a58e13f6"`              |
| partitionKey:         | `"[customer_id]:[product_sku]:events:[year]:[month]"` |
| partitionKey example: | `"1061737:actions_storage:events:[year]:[month]"`     |

### Customer Events Rollup

|                       |                                                                                        |
| --------------------- | -------------------------------------------------------------------------------------- |
| id:                   | `"[customer_id]:[:product_sku]:events:rollup:[year]:[month]:[day]:[org_id]:[repo_id]"` |
| id example:           | `"1061737:actions_storage:events:rollup:2023:7:13:30846345:238790217"`                 |
| partitionKey:         | `"[customer_id]:[product_sku]:events:rollup"`                                          |
| partitionKey example: | `"1061737:actions_storage:events:rollup"`                                              |

</details>

## High Watermark

<details>

<summary>Expand</summary>

### Customer Events

|                       |                                          |
| --------------------- | ---------------------------------------- |
| id:                   | `"[uuid]"`                               |
| id example:           | `"720e7d11-45fe-55f5-b57f-5bd0a58e13f6"` |
| partitionKey:         | `"[customer_id]:[product_sku]:events"`   |
| partitionKey example: | `"1061737:copilot_for_business:events"`  |

## Subscriptions ("actual current total seat count")

|                       |                                                |
| --------------------- | ---------------------------------------------- |
| id:                   | `"[customer_id]:highWatermark:[product_sku]"`  |
| id example:           | `"1061737:highWatermark:copilot_for_business"` |
| partitionKey:         | `"[customer_id]:highWatermark:[product_sku]"`  |
| partitionKey example: | `"1061737:highWatermark:copilot_for_business"` |

## Subscriptions to bill for a given month ("high watermark")

|                       |                                                              |
| --------------------- | ------------------------------------------------------------ |
| id:                   | `"[customer_id]:highWatermark:[product_sku]:[year]:[month]"` |
| id example:           | `"1061737:highWatermark:copilot_for_business:2023:11"`       |
| partitionKey:         | `"[customer_id]:highWatermark:[product_sku]:[year]:[month]"` |
| partitionKey example: | `"1061737:highWatermark:copilot_for_business:2023:11"`       |

## Individual Subscription records

|                       |                                                |
| --------------------- | ---------------------------------------------- |
| id:                   | `"subscription:[actor_id]"`                    |
| id example:           | `"subscription:12345"`                         |
| partitionKey:         | `"[customer_id]:highWatermark:[product_sku]"`  |
| partitionKey example: | `"1061737:highWatermark:copilot_for_business"` |

</details>

## Zuora Emission

<details>

<summary>Expand</summary>

### Zuora Emission Rollup

Each roll up item represents an aggregate total of an Zuora customer's usage for the specified SKU in a one day period. These records are used to send a customer's usage to Zuora on a daily basis. See our [Zuora emission docs](https://github.com/github/billing-platform/blob/main/docs/reference/features/emissions/zuora-emissions.md) for more details.

|                       |                                                      |
| --------------------- | ---------------------------------------------------- |
| id:                   | `"[customer_id]:[product_sku]:[year]:[month]:[day]"` |
| id example:           | `"77700544:packages_storage:2024:9:1"`           |
| partitionKey:         | `"[product_sku]:[year]:[month]:[day]:byZuoraEmission"`             |
| partitionKey example: | `"packages_storage:2024:9:1:byZuoraEmission"`                        |

<details>

<summary>Example Item</summary>

``` json
[{
  "partitionKey": "packages_storage:2024:9:1:byZuoraEmission",
  "id": "77700544:packages_storage:2024:9:1",
  "BilledAmount": 1773360,
  "FullQuantity": 5277609360,
  "Quantity": 5277609360,
  "AppliedCostPerQuantity": 336020,
  "FractionalQuantity": 0,
  "Pricing": {
    "partitionKey": "pricing",
    "id": "packages_storage",
    "Price": 336020,
    "Product": "packages",
    "Sku": "packages_storage",
    "MeterType": 1,
    "FriendlyName": "Packages storage",
    "AzureMeterId": "832bfa96-c7db-416b-aa5b-6ea89054d493",
    "EffectiveDatePrices": null,
    "FreeForPublicRepos": true,
    "EffectiveAt": 1714521600,
    "UnitType": 9
  },
  "EntityDetail": {
    "CustomerId": "77700544",
    "CostCenterDetail": {
      "EnterpriseCustomerId": "77700544",
      "CostCenterUUID": "",
      "IsCostCenterProxy": false,
      "CostCenterState": 0
    }
  },
  "UsageAt": 1725148800000,
  "_rid": "5mFXAK7x5hrzStcAAADHBA==",
  "_self": "dbs\/5mFXAA==\/colls\/5mFXAK7x5ho=\/docs\/5mFXAK7x5hrzStcAAADHBA==\/",
  "_etag": "\"8100c643-0000-0100-0000-66d4f1f10000\"",
  "_attachments": "attachments\/",
  "_ts": 1725231601
}]

```

</details>

### Zuora Emission Records

These items store information about a Zuora customer's usage submitted for all product/SKU on a given day. The header will include all products and SKUs transmitted to Zuora for that day. The partition will contain one item per month, updated daily, to include all customer products and SKUs with their usage for each day.
|                       |                                                                    |
| --------------------- | ------------------------------------------------------------------ |
| id:                   | `"[customer_id]:Emission:[year]:[month]:[day]"` |
| id example:           | `"77700544:Emission:2024:9:1"`                  |
| partitionKey:         | `"[customer_id]:Emission:[year]:[month]"`       |
| partitionKey example: | `"77700544:Emission:2024:9"`                     |



<details>

<summary>Example Item</summary>

```json
[{
  "partitionKey": "77700544:Emission:2024:9",
  "id": "77700544:Emission:2024:9:1",
  "UsagePartitionKey": "",
  "CostCenter": "",
  "UsageTotal": {
    "Gross": 337.466844071,
    "Discount": 6.691357671,
    "Net": 330.7754864,
    "Quantity": 888.327759478
  },
  "ProductTotals": {
    "actions": {
      "Product": "actions",
      "UsageTotal": {
        "Gross": 7.485063812,
        "Discount": 6.685063812,
        "Net": 0.8,
        "Quantity": 852.888225555
      },
      "SkuTotals": {
        "actions_linux": {
          "Sku": "actions_linux",
          "UsageTotal": {
            "Gross": 6.272,
            "Discount": 6.272,
            "Net": 0,
            "Quantity": 784
          },
          "BillingItems": [
            {
              "partitionKey": "77700544:2024:9:1",
              "id": "77700544:actions_linux:2024:9:1:0",
              "BilledAmount": 456000000,
              "FullQuantity": 57000000000,
              "Quantity": 57000000000,
              "AppliedCostPerQuantity": 8000000,
              "FractionalQuantity": 0,
              "Pricing": {
                "partitionKey": "pricing",
                "id": "actions_linux",
                "Price": 8000000,
                "Product": "actions",
                "Sku": "actions_linux",
                "MeterType": 0,
                "FriendlyName": "Actions Linux",
                "AzureMeterId": "3dbfec75-284c-4c89-8c9c-0d395be81a0c",
                "EffectiveDatePrices": null,
                "FreeForPublicRepos": true,
                "EffectiveAt": 1689366600,
                "UnitType": 2
              },
              "EntityDetail": {
                "CustomerId": "77700544",
                "CostCenterDetail": {
                  "EnterpriseCustomerId": "77700544",
                  "CostCenterUUID": "",
                  "IsCostCenterProxy": false,
                  "CostCenterState": 0
                }
              },
              "UsageAt": 1725149011970
            },]

```

</details>

## Zuora Emission Batch Status

These items store the status of Zuora emission batches. Each batch status record represents the state of a batch of usage records that are being processed for submission to Zuora.

|                       |                                                                    |
| --------------------- | ------------------------------------------------------------------ |
| id:                   | `"zuoraEmissionBatchStatus:[year]:[month]:[day]:[batchNumber]"`  |
| id example:           | `"zuoraEmissionBatchStatus:2024:9:1:1"`                            |
| partitionKey:         | `"zuoraEmissionBatchStatus:[year]:[month]:[day]"`                  |
| partitionKey example: | `"zuoraEmissionBatchStatus:2024:9:1"`                              |
<details>

<summary>Example Item</summary>

```json
[{
  "partitionKey": "zuoraEmissionBatchStatus:2024:9:1",
  "id": "zuoraEmissionBatchStatus:2024:9:1:1",
  "BatchNumber": 1,
  "Status": "Building",
  "PayloadSize": 1024,
  "TotalRecordCount": 100,
  "_rid": "5mFXAK7x5hrzStcAAADHBA==",
  "_self": "dbs/5mFXAA==/colls/5mFXAK7x5ho=/docs/5mFXAK7x5hrzStcAAADHBA==/",
  "_etag": "\"8100c643-0000-0100-0000-66d4f1f10000\"",
  "_attachments": "attachments/",
  "_ts": 1725231601
}]
```

</details>



## Zuora Emission Batch
These items store the details of Zuora emission batches. Each batch record represents a batch of usage records that are being processed for submission to Zuora.


|                       |                                                                    |
| --------------------- | ------------------------------------------------------------------ |
| id:                   | `"customer:[customer_id]"`                                         |
| id example:           | `"customer:77700544"`                                               |
| partitionKey:         | `"zuoraEmissionBatch:[year]:[month]:[day]:batch-[batchNumber]"`    |
| partitionKey example: | `"zuoraEmissionBatch:2024:9:1:batch-1"`                            |

<details>
<summary>Example Item</summary>

```json
[{
  "partitionKey": "zuoraEmissionBatch:2024:9:1:batch-1",
  "id": "customer:77700544",
  "UploadUsageRecords": [
    {
      "CustomerId": "77700544",
      "UsageIdentifier": "actions_linux",
      "UsageDate": "2024-09-01T00:00:00Z",
      "Amount": 100
    }
  ],
  "_rid": "5mFXAK7x5hrzStcAAADHBA==",
  "_self": "dbs/5mFXAA==/colls/5mFXAK7x5ho=/docs/5mFXAK7x5hrzStcAAADHBA==/",
  "_etag": "\"8100c643-0000-0100-0000-66d4f1f10000\"",
  "_attachments": "attachments/",
  "_ts": 1725231601
}]
```
</details>
</details>
