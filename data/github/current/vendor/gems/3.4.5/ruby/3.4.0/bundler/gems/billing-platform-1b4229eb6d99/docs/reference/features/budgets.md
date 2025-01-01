# Budgets in billing-platform

Customers on billing-platform can create budgets targeting different TargetTypes and products. A `TargetType` refers to the entity scope and customers have several options including enterprise, organization, repo and cost center. For example, a customer can create an Actions budget for the entire enterprise or a Codespaces budget for a particular cost center. We have validations in place to ensure a customer can only have one budget for a given `TargetType` and product combination, i.e. a customer can only have one enterprise scoped budget for Actions.

In the budget db record, the product for a budget is defined by the `PricingTargetId` and `PricingTargetType`. We currently only have product-scoped budgets implemented but we will most likely add support for SKU level budgets in the future. The different `PricingTargetTypes` are defined [here](https://github.com/github/billing-platform/blob/5afc968f11428c6c5ae85495ddd1f753734e8d61/lib/models/budget.go#L86C1-L90C2).

These budgets can be used to limit spend or for alerting purposes, which is determined by the `BudgetLimitType` of a budget. There are several different budget limit types that are defined [here](https://github.com/github/billing-platform/blob/5afc968f11428c6c5ae85495ddd1f753734e8d61/lib/models/budget.go#L44).

Budgets are stored in Cosmos under the `customer:<customerId>:budgets` partition key. An example budget record is below.

``` json
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

We keep track of how much usage has been applied to a budget by creating a budget state record for each budget a customer creates.

ℹ️ Usage is not applied to a budget state until a customer has exhausted all of their applicable discounts.

An example budget state record is below.

``` json
{
  "CurrentAmount": 50772163576843, // Monetary amount of usage applied towards the budget
  "IsFullyFunded": false,
  "Quantity": 7164430048784171,
  "TargetAmount": 100000000000000, // The monetary budget amount set by the customer
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

## Table of Contents

- [Terminology](#terminology)
- [Feature details](#feature-details)
  - [Using budgets to limit spend](#using-budgets-to-limit-spend)
  - [Default budgets](#default-budgets)
  - [Overages](#overages)
  - [Multiple budgets](#multiple-budgets)
  - [How does the budget and overage calculation fit into the usage processing flow](#how-does-the-budget-and-overage-calculation-fit-into-the-usage-processing-flow)
  - [Budget alerts](#budget-alerts)
- [Troubleshooting](#troubleshooting)
- [FAQ](#faq)
- [References](#references)

## Terminology

- **Hard limit**: This is a budget that will prevent spend once the limit is reached. It will also alert the users selected while creating the budget.
  - The `budgetLimitType` property on the budget struct is either `PreventFurtherUsage` or `StopActiveUsage`. https://github.com/github/billing-platform/blob/140090f79101fc72c6d71b5716fcd1372aec3d62/lib/models/budget.go#L78-L80
- **Soft limit**: This is a budget that will only alert users but won't prevent spend. The customer will be able to continue using the product after the budget limit is reached. They will also be billed for the usage past the budget limit.
  - The `budgetLimitType` property on the budget struct is either `AlertingOnly` or `IgnoreLimit`. https://github.com/github/billing-platform/blob/140090f79101fc72c6d71b5716fcd1372aec3d62/lib/models/budget.go#L74-L76
- **High watermark**: Seat-based products

## Feature details

### Using budgets to limit spend

In order for the budget to block any spending beyond the set amount, customers have to select the "Stop usage when budget limit is reached" option when creating or editing a budget.
If that option isn’t selected, the budget will only serve for alerting customers when they’re nearing the limit, but will allow usage to continue past its limit.

<img width="537" alt="screenshot of new budget box with a $0 budget selected and the 'Stop usage when budget limit is reached' box checked" src="https://github.com/github/billing-platform/assets/20481048/f9293541-b7ff-4f52-b336-d543cda7f2c5"/>

### Default budgets

If customers want to limit spend, they need to create their own budgets. By default, they’re allowed to spend as much as they’d like. There’s no default budget.
The only exception relates to enterprises on trial. These customers are only allowed to spend the included discounts, [which are documented here](https://docs.github.com/en/enterprise-cloud@latest/admin/overview/setting-up-a-trial-of-github-enterprise-cloud#what-is-included-in-the-trial).

### Overages

When a customer configures a budget and selects the "Stop usage" checkbox, we will not allow any usage beyond that amount.
Given the distributed nature of our services, there may already be usage in progress when the limit is reached and there's a good chance customers will use slightly more than their budget allows. If that happens, GitHub will cover that overage expense. We will not charge customers for it and we won't display that overage amount in the UI, API or usage reports.

Once a customer has reached their budget limit, usage will be shutoff for that product and entity. For example, if an Actions budget for organization A has been reached, they won't be able to start new Action workflow runs, but other organizations within the enterprise will.
This mechanism is powered by our [`canProceedWithusage` endpoint](https://github.com/github/billing-platform/blob/main/docs/reference/features/can-proceed-with-usage.md), which all partner teams call before sending us usage.

The experience of shutting off services will be different for each product, but here's an example of what customers will see for Actions.

![A failed Actions job with an annotation that says "The job was not started because recent account payments have failed or your spending limit needs toe be increased. Please check the 'Billing & plans' sections in your settings".](https://github.com/github/billing-platform/assets/20481048/607e3018-55ed-465c-989f-86a097d02c49)

We report overages internally in the `UsageLineItem` hydro topic. Here's a sample Kusto query you can run to find overage amount and overage quantity.

```
database('hydro').billingplatform_v1_usage_line_item
| project timestamp, overage_amount, overage_quantity, sku, customer_id
| where customer_id == ['_customerId'] and overage_amount > 0
```

### Multiple budgets

What happens when some usage reported applies to multiple budgets?
For example, if I have a budget for organization A and another budget for its parent enterprise. When we receive usage associated with organization A, that usage will be included in both budgets, since both apply.

What if there are overages incurred from these budgets?
In that case, we will calculate overages incurred from each budget and will update the usage amount that applies based on the highest overage amount.
Here's an example scenario with 3 budgets:

![A diagram of overages and how they are impacting different budget types.](https://github.com/github/billing-platform/assets/20481048/02c65cf3-873f-43d9-b6d2-ff8a6687e8ee)

### How does the budget and overage calculation fit into the usage processing flow

1. We [calculate discounts](https://github.com/github/billing-platform/blob/main/docs/reference/features/discounts.md). This means applying discounts to the value of the item in the order of:
   1. Public repo discount
   2. Plan discount (formerly referred to as entitlements, what is "free" with the plan)
   3. Configured discount (max. configured amount of % or $ discount)
3. We will find all applicable budgets (cost centers, organization, enterprise)
4. We will calculate the maximum amount of overage for each applicable budget
   - `overage amount = (current amount + new amount) - budget target amount`
5. If there are overages AND the budget is a "stop usage" budget, we will remove that from the item's cost
6. We will add a `UsageLineItem` for the item (including the discount total and the item total after overages are removed)
7. We will update the state of the budgets
8. We will kick off all applicable rollup items

![A diagram of the above usage processing flow with respect to budgets.](https://github.com/github/billing-platform/assets/20481048/c661ad30-e957-483f-acec-0afb338b9951)

### Budget Alerts

When setting up a budget, customers have the option of receiving alerts when certain budget thresholds are met. Currently, these thresholds are set to 75%, 90% and 100% for all customers. If a customer opts to receive alerts, they will see banners in the billing UI as well as receive email notifications when these thresholds are met.

Budget alerts are implemented using the [`billingplatform.v1.BudgetThresholdNotification`](https://hydro.githubapp.com/kafka/clusters/potomac/topic?topic=billingplatform.v1.BudgetThresholdNotification) Hydro topic. In the `usageHandler`, when [updating budget states based on new usage](https://github.com/github/billing-platform/blob/5afc968f11428c6c5ae85495ddd1f753734e8d61/lib/messaging/handlers/usageHandler.go#L570), we also call the [`PublishBudgetStateThresholdMessage` method](https://github.com/github/billing-platform/blob/5afc968f11428c6c5ae85495ddd1f753734e8d61/lib/engines/customer.go#L824), which will publish a Hydro message if a budget is alertable and a threshold has been reached. In the dotcom code, we have a [processor](https://github.com/github/github/blob/adf128e361798942c53fc20a58806f58ec8c1562/lib/github/stream_processors/billing_platform/budget_threshold_notification_processor.rb) that is subscribed to this Hydro topic and contains logic to show banners and send emails when a message is received.

## Troubleshooting

- How to view a customer's budget when assisting them?

The stafftools budget view mirrors what customers can see, so we should rely on that when answering customer questions.
Go to enterprise stafftools > Billing & Licensing > Budgets. Example link for Avocado Corp https://admin.github.com/stafftools/enterprises/avocado-corp/billing/budgets

- How to find out when a budget was created or updated?

Audit logs can help you out, just use the following query:

```
webevents | where (business_id == {enterprise_id}) and action startswith 'billing.budget'
```

This will include both budget creation and update events. It includes who performed it, what was the target amount set and the target resource. It does _not_ include whether the "stop usage" checkbox was checked or not.

## FAQ

- **How do I tell if a budget is set to stop usage or alerting?** If you want to see whether the budget stops usage, you have to go to the budgets index page > click the 3 dots button > Edit and check if the "Stop usage..." box is checked.

  ![Screenshot of two budgets, one that is under budget and one that is over budget. There is nothing visible in this UI stating that a budget is will stop usage or not.](https://github.com/github/billing-platform/assets/20481048/ca4ca233-02e3-4a89-8e31-16c74545f7fc)

  The same is true for emails. When we alert customers that their budget has been reached, there's no indication as to whether that budget will stop further usage or if it's an alerting only budget.

  - Issue tracking that https://github.com/github/gitcoin/issues/15560.

- **Is usage incurred previous to the budget creation included in the budget?** No. For example, if the customer has already used $100 worth of Actions minutes, then they create an Actions budget, that will start off at $0 and any subsequent usage will count towards it.

- **When budgets are created or updated, customers can’t see when that happened or who did it.** That information is available in audit logs in stafftools however. Here's the query:

  ```
  webevents | where (business_id == {enterprise_id}) and action startswith 'billing.budget'
  ```

  This will include both budget creation and update events. It includes who performed it, what was the target amount set and the target resource. It does _not_ include whether the "stop usage" checkbox was checked or not.

- **Does usage covered by discounts get included in the budget?** No. For example, we receive Codespaces usage amount of $10. The customer has a 50% discount. In this case, only $5 will be counted in the budget since the remaining $5 is covered by discounts.

- **Who can create budgets for a repository scope?** Users are only able to create budgets with a repository scope if they’re an owner for one of the organizations within the enterprise. (As of this moment, billing-platform is not supported for organizations).

  ![New budget page budget scope section with `Repository` selected](https://github.com/github/billing-platform/assets/20481048/b1177675-0c78-45ea-b373-a710da9fd569)

- **Which products can create "Stop usage" hard-limit budgets?** Seat-based products cannot currently create hard-limit budgets, only alerting budgets. That's because we can't stop usage of seat-based products once the budget is reached. When a seat is assigned, we provide access to that feature through the end of the month.

- **Customers can set budgets for organizations, repositories and cost centers that are higher than an enterprise-wide budget.** For example, if there is an Enterprise Actions budget of $10,000 per month, we will not prevent the user from creating a Cost center Actions budget of $100,000 per month.

## References

- [Product budget spec](https://docs.google.com/document/d/12cPotrLUXhxaCUXbOureNlFI1pDAvS81UqY6lniigWg/edit#heading=h.dslkkx6mpq6k)
- [Budget limits and overages engineering blueprint](https://docs.google.com/document/d/1tw8WOufoEWnJ5dcOwxmelfQ6F2tqnk-kTSw6QrkFFH0/edit#heading=h.hh726zbt20t0)
