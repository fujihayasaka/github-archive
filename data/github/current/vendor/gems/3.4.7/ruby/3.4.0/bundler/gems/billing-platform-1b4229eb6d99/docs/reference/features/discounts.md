# Discounts

Discounts are the entities set up to deduct from the cost of a GitHub item.

## Table of Contents

- [Terminology](#terminology)
- [Feature details](#feature-details)
  - [Discount definitions](#discount-definitions)
  - [Discount state](#discount-state)
  - [Discount rollups](#discount-rollups)
  - [Other discount types](#other-discount-types)
  - [Flow of applying discounts](#flow-of-applying-discounts)
- [Troubleshooting](#troubleshooting)
- [References](#references)

## Terminology

- **Plan Discounts (Entitlements)**: Discounts included with an entity's plan, such as the free Actions minutes available per plan.

## Feature details

### Discount definitions

All the initial setup for discounts is stored under `customer:<customer-id>:discounts` partition.
There you can check discount's targets and amounts.

<details>

<summary>Discount document</summary>

```json
{
 "partitionKey":"customer:9370667:discounts",
 "id":"27a1d5bc-c5cc-4288-9818-a53b85ec915b",
 "Uuid":"27a1d5bc-c5cc-4288-9818-a53b85ec915b",
 "CustomerId":"9370667",
 "Percentage":50,
 "TargetAmount":0,
 "Targets":[
  {
   "Id":"9370667",
   "Type":5
  }
 ],
 "StartDate":1687824000,
 "EndDate":1719446400,
 ...
}
```

</details>

We have $ discounts and % discounts - first ones act as a coupon (i.e. customer gets X dollars off their bill) and second ones reduce cost by a certain percentage.

Ideally, we should have enums to distinguish the types, but for now:

- `Percentage` is 0 for $ discounts and float value otherwise (e.g. 50.5%)
- `TargetAmount` is 0 for % discounts and int64 values otherwise (representing dollar amounts stored as nano cents)

Discounts can be applied to a SKU, product, repo, org or the whole enterprise. These are known as discount targets.

Discount target is a pair of `id` and `type`. Here is a mapping between discount types and ids:

| DiscountTargetType | DiscountTargetId | Example |
|--------|--------|--------|
| `SkuDiscount` | `Sku` field of `models.OldPrice` | `"ghas_seats"` |
| `ProductDiscount` | `Product` field of `models.OldPrice` | `"git_lfs"` |
| `RepoDiscount` | ID of the repo in Dotcom | `"15"` |
| `OrgDiscount` | ID of the org in Dotcom | `"682"` |
| `EnterpriseDiscount` | ID of the `Customer` that is associated with that `Business` in Dotcom | `"8368"` |

Refer to [`GetTargetIdByTargetType`](https://github.com/github/billing-platform/blob/f70e16410a8bc8c30dcf651dc8ea3839d469cb52/lib/models/discount.go#L145-L171) for more details.

`StartDate` and `EndDate` are dates between which a discount is valid and can be applied to usage. They're set as a UNIX timestamp in UTC.

### Discount state

Additionally, we have a partition that tracks the discount state for the current month under `customer:<customer-id>:discounts:<discount-uuid>:yyyy:mm`.

It contains one document with ID `discountState` which has fields like `IsFullyApplied`, `CurrentAmount` and `TargetAmount`.

> [!NOTE]
> `IsFullyApplied` is never `true` for % discounts.

<details>

<summary>Discount State document</summary>

```json
{
{
    "partitionKey": "customer:1:discounts:85679075-fe74-461e-9c22-808ac1393944:2023:7",
    "id": "discountState",
    "Customer": { ... },
    "IsFullyApplied": false,
    "CurrentAmount": 8000000,
    "TargetAmount": 400000000000,
    "Uuid": "85679075-fe74-461e-9c22-808ac1393944",
    ...
}
}
```

</details>

Other documents in that partition will have IDs of the line items which went into that discount.
Each of those documents, besides amounts and quantities that belong to the line item,
will have an additional field `AmountApplied` indicating how much of the `BilledAmount` went into the discount.

### Discount rollups

Rollups for discounts have the same structure as [rollups for usage](https://github.com/github/billing-platform/blob/e704b906a4a1402763a3e4727613928018b01126/docs/database_structure.md#visualizing-usage-in-logical-partitions), just with `:discount` suffix:

```
<customer-id>:<sku>:2023:6:26:15:discount (also by day/month/year)
<customer-id>:2023:6:26:15:discount
```

We only store discounts by customer and by customer+SKU

1. By customer are used for calculating the net amount for Zuora emissions
2. By customer+SKU is used for calculating the net quantity for Azure emissions

### Other discount types

#### Public repo discounts

Since we ingest any & all usage, we need to discount public repos at 100%. For that we create a "dynamic" 100% discount which gets applied before anything else, and stops processing any other discounts after that.

The UUID of that discount is static meaning it's state can always be tracked under the `customer:<customer-id>:discounts:9cdf0dca-1b19-11ee-be56-0242ac120002:yyyy:mm` partition.

https://github.com/github/billing-platform/blob/57ea13411ebea88a5d594b8bbda471037993b18d/lib/models/discount.go#L10

To determine whether a given repo is public or not, we have a [Hydro consumer](https://github.com/github/billing-platform/blob/57ea13411ebea88a5d594b8bbda471037993b18d/lib/hydro/handlers/repository_visiblity_changed_handler.go#L29) in place that listens to the `github.repositories.v1.VisibilityChanged` event and updates the metadata. We also have a [direct call to dotcom](https://github.com/github/billing-platform/blob/57ea13411ebea88a5d594b8bbda471037993b18d/lib/engines/customer.go#L199) to fetch the initial metadata during usage ingestion.

#### Plan discounts

Included usage is also discounted. These are SKU $ discounts translated from the
former "entitlements" usage. For that we have [hardcoded $ discounts](https://github.com/github/billing-platform/blob/6469811963a565f55c5de44db8415ab4f8f00b30/lib/engines/customer.go#L625)
based on a customer's plan - these discounts applied only to small set of SKUs and
have higher priority compared to % discounts and other customer $ discounts.

They are also shared between the general enterprise usage and the cost center usage
(i.e. cost center don't have their own entitlements - they consume only enterprise entitlements).

### Flow of applying discounts

1. Public repo discounts
2. Plan discounts (a.k.a "entitlements" discounts)
3. $ Discounts
4. % Discounts

Targets for $ and % discounts are stacked on top of each other and applied in a following order:

```
SKU -> Product -> Repo -> Org -> Enterprise
```

## Troubleshooting

- Useful queries for testing:

    ```sql
    -- verify that total AmountApplied is equal to TargetAmount
    -- when FullyApplied == true
    SELECT SUM(c.AmountApplied) FROM c
    WHERE c.partitionKey = "customer:<customer-id>:discounts:<discount-UUID>:2023:6" AND c.id != "discountState"

    -- verify line items to which a $ discount was applied
    SELECT c.id, c.BilledAmount, c.Quantity, c.Pricing.Sku FROM c
    WHERE c.partitionKey = "customer:<customer-id>:discounts:<discount-UUID>:2023:6" AND c.id != "discountState"

    -- verify that CurrentAmount is equal to the total sum of AmountApplied
    SELECT SUM(c.AmountApplied) FROM c
    WHERE c.partitionKey = "customer:<customer-id>:discounts:<discount-UUID>:2023:6" AND c.id != "discountState"

    -- verify that both queries return the same number of items
    SELECT COUNT(1) FROM c
    WHERE c.partitionKey = "9370820:actions_linux:2023:6:27" AND c.id != "total"

    SELECT COUNT(1) FROM c
    WHERE c.partitionKey = "9370820:actions_linux:2023:6:27:discount" AND c.id != "total"
    ```

## References

- [ADR: Budget state after discount](https://github.com/github/gitcoin/tree/main/docs/technical/architecture-decision-record/0046-budget-state-after-discount.md)
- [How to create a discount manually](../../how-to-guides/how-to-create-a-discount-manually.md)
