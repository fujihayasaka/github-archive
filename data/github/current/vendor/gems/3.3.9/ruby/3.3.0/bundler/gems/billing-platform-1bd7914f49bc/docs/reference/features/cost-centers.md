# Cost Centers

Cost centers are designed to group the expenses / metered billing usage of an operational department within an enterprise. Enterprises can create multiple cost centers. A costcenter consists of multiple _resources_. A _resource_ can be an organization, repository  or users. If a resource is part of a costcenter, all its usage will be attributed to the costcenter. By default, the billing target for a costcenter is the same as the enterprise's. However, for Azure customers, the billing target could be set to a different Azure subscription.

## Table of Contents

- [Terminology](#terminology)
- [Feature details](#feature-details)
  - [Creating and editing cost centers](#creating-and-editing-cost-centers)
  - [Deleting cost centers](#deleting-cost-centers)
  - [Implementation details](#implementation-details)
  - [Relevant models](#relevant-models)
  - [Queries](#queries)
  - [API](#api)
  - [UI](#ui)
- [References](#references)

## Terminology

- **Resource**: The collection of items grouped within a cost center. Can be an organization, repository, or a user.
- **Billing Target**: A cost center's billing target refers to the details for billing the account. The type is either Zuora or Azure subscription, and the ID if present refers to an Azure Subscription ID.

## Feature details

### Creating and editing cost centers

- A cost center can be created by either an enterprise admin or an org level admin. Note that an enterprise admin can only add orgs. Repos can only be added by the admin of the org that owns the repo. Currently users can be added only in the API.

- A resource can only be added to a single cost center and customers will be shown an error if they attempt to add a resource to a cost center that is already associated with another cost center. Once a resource is added to a cost center, all of the resource's metered usage will be tracked by the cost center.
- Customers have the option to create budgets that are scoped to a specific cost center.
- A cost center's name and Azure ID (for Azure enterprises) can be edited after creation. Also, resources can be added or removed from a cost center.

  - adding orgs/repos: any usage accrued against the added org/repo will immediately start being billed against the cost center
  - removing orgs/repos: any usage accrued against the removed org/repo will immediately start being billed against the enterprise
  - adding a user: any usage accrued for the user (a seat) will immediately start being billed against the cost center. however, if the seat for the user was added before the user was added to the cost center, then the user's seat will only start being charged against the cost center at the start of the next bill cycle.
  - removing a user: any usage accrued for the user (a seat) will immediately start being billed against the enterprise. however, if the seat for the user was added before the user was removed from the cost center, then the user's seat will only start being charged against the enterprise at the start of the next bill cycle.

### Deleting cost centers

- A cost center can be deleted by an enterprise admin or an org level admin. When a cost center is deleted, all resources associated with the cost center will be removed from the cost center and will be billed against the enterprise.
- The deleted cost center is still available on the usage page to view historical usage.
- The deleted tab contains the deleted cost centers and their details (like resources that were previously in them) can be viewed.

### Implementation details
A Cost center is modeled in Cosmos across different documents types. A type of document is identified by its partition key and id.
A Cost Center consists of :
1. A costcenter document
2. A costcenter resource lookup document
3. A costcenter proxy document<br/>
1, and 2 are in the same partition and 3 is in a different partition.<br/>

Below are the details of each document:<br/>

#### 1. A [Cost Center](https://github.com/github/billing-platform/blob/main/lib/models/costCenter.go#L69) document

The Cost Center document contains all details about the cost center. It is unique per cost center and consists of the following fields:

- `partitionKey:"customer:<customer id>:costCenters"` and id is unique uuid of costCenter
- customer field contains the parent enterprise's details
- cost center's name
- billing target type (zuora or azure subscription)
- billing target id (if the enterprise's billing target type is azure subscription then this field could be set to an azure subscription id)
- resources (orgs, repos, users) associated with the cost center. Note these are embedded resources with the id and type of the resource. The resources relationship to the cost center is also enforced through the Cost Center Resource Lookup document(see below). These two should always be in [sync](https://github.com/github/billing-platform/blob/main/lib/engines/costCenter.go#L154) on create and update.
- Cost center state (active 0 or inactive 1). By default all cost centers are active on creation. When a cost center is deleted, this document's  state is set to inactive. Also the cost center proxy documents's cost center state is set to inactive.The Resource Lookup document and Target Look up documents types are deleted when a cost center is deleted.

<details>

<summary>sample cost center document</summary>

``` json
{
    "partitionKey": "customer:1:costCenters",
    "id": "0b58ba15-aede-4931-a6f6-51f4e16bab74",
    "Customer": {
        "partitionKey": "customer:1",
        "id": "customer",
        "EnterpriseCustomerId": "1",
        "CostCenterUUID": "",
        "IsCostCenterProxy": false,
        "CostCenterState": 0,
        "BillingTarget": 0,
        "AzureAccountId": "",
        "ZuoraAccountId": "",
        "ZuoraAccountNumber": "",
        "EnabledProducts": [],
        "EffectiveAt": 0,
        "DiscountPlanName": "",
        "BillForPublicRepoUsage": false,
        "HasPaymentMethod": false,
        "HasZuoraSubscription": false,
        "IsBillingLocked": false,
        "TradeScreening": {
            "HasAnyTradeRestrictions": false,
            "HasFullTradeRestrictions": false,
            "FeaturesWithCommercialInteractionRestrictions": null
        }
    },
    "TargetType": 2,
    "TargetId": "",
    "UUID": "0b58ba15-aede-4931-a6f6-51f4e16bab74",
    "Name": "MyCC1",
    "Resources": [
        {
            "Id": "4",
            "Type": 4
        },
        {
            "Id": "1",
            "Type": 3
        }
    ],
    "CostCenterState": 0,
    "_rid": "pEMIAOfzVKsCAAAAAAAAAA==",
    "_self": "dbs/pEMIAA==/colls/pEMIAOfzVKs=/docs/pEMIAOfzVKsCAAAAAAAAAA==/",
    "_etag": "\"70013895-0000-0700-0000-65f090d80000\"",
    "_attachments": "attachments/",
    "_ts": 1710264536
}
```

</details>

#### 2. A CostCenter Resource Lookup document

The CostCenter Resource Lookup document represents the relationship between a costcenter and a resource (org or repo or user ). It consists of the following fields:
* `partitionKey:"customer:<customer id>:costCenters"` and id is of the format `resourceLookup:repository:<repository id>` or `resourceLookup:owning_entity:<organization id>` or `resourceLookup:user:<user id>`
* Customer field contains the costcenter customer proxy details
* Target Type and TargetId are also present in this document but are not relevant here. It is due to re-using the [CostCenterKey](https://github.com/github/billing-platform/blob/main/lib/models/costCenter.go#L64) struct to create this document.

<details>

<summary> sample resource lookup document </summary>

``` json
{
    "partitionKey": "customer:1:costCenters",
    "id": "resourceLookup:repository:1",
    "Customer": {
        "partitionKey": "customer:0b58ba15-aede-4931-a6f6-51f4e16bab74",
        "id": "customer",
        "EnterpriseCustomerId": "1",
        "CostCenterUUID": "0b58ba15-aede-4931-a6f6-51f4e16bab74",
        "IsCostCenterProxy": true,
        "CostCenterState": 0,
        "BillingTarget": 1,
        "AzureAccountId": "",
        "ZuoraAccountId": "",
        "ZuoraAccountNumber": "",
        "EnabledProducts": [],
        "EffectiveAt": 0,
        "DiscountPlanName": "",
        "BillForPublicRepoUsage": false,
        "HasPaymentMethod": false,
        "HasZuoraSubscription": false,
        "IsBillingLocked": false,
        "TradeScreening": {
            "HasAnyTradeRestrictions": false,
            "HasFullTradeRestrictions": false,
            "FeaturesWithCommercialInteractionRestrictions": null
        }
    },
    "TargetType": 2,
    "TargetId": "",
    "UUID": "0b58ba15-aede-4931-a6f6-51f4e16bab74",
    "_rid": "pEMIAOfzVKsFAAAAAAAAAA==",
    "_self": "dbs/pEMIAA==/colls/pEMIAOfzVKs=/docs/pEMIAOfzVKsFAAAAAAAAAA==/",
    "_etag": "\"70013b95-0000-0700-0000-65f090d80000\"",
    "_attachments": "attachments/",
    "_ts": 1710264536
}
```
</details>

#### Notes:
- Because the "id" does not include details about the costcenter, Cosmos  will implicitly ensure a resource can appear only once across a customer's costcenters . In other words, a repo/org/user can be only in one costcenter at a time( for a customer). However we do [validations](https://github.com/github/billing-platform/blob/main/lib/models/costCenter.go#L200) in code to check this before it hits cosmos.
- When a cost center is archived, we remove the resource look up documents immediately. This allows the customer to be able to use that resource in a new cost center

#### 3. A proxy Cost Center Customer document

The  proxy Cost Center [Customer](https://github.com/github/billing-platform/blob/main/lib/models/customer.go#L33-L59) document represents the cost center  as a Customer document (with the [IsCostCenterProxy](https://github.com/github/billing-platform/blob/main/docs/cost-centers/cost_centers.md#what-is-the-customeriscostcenterproxy-field-)) field set to true so we can treat it as a customer and do emissions towards usage incurred to the resources in the cost center.
The proxy Cost Center Customer document is unique per cost center and contains

- `partitionKey:"customer:<costcenter id>"` and `id:"customer"`
- Its `IsCostCenterProxy` field is always true


<details>

<summary>sample proxy cost center document</summary>

```json
{
    "partitionKey": "customer:0b58ba15-aede-4931-a6f6-51f4e16bab74",
    "id": "customer",
    "EnterpriseCustomerId": "1",
    "CostCenterUUID": "0b58ba15-aede-4931-a6f6-51f4e16bab74",
    "IsCostCenterProxy": true,
    "CostCenterState": 0,
    "BillingTarget": 1,
    "AzureAccountId": "",
    "ZuoraAccountId": "",
    "ZuoraAccountNumber": "",
    "EnabledProducts": [],
    "EffectiveAt": 0,
    "DiscountPlanName": "",
    "BillForPublicRepoUsage": false,
    "HasPaymentMethod": false,
    "HasZuoraSubscription": false,
    "IsBillingLocked": false,
    "TradeScreening": {
        "HasAnyTradeRestrictions": false,
        "HasFullTradeRestrictions": false,
        "FeaturesWithCommercialInteractionRestrictions": null
    },
    "_rid": "pEMIAOfzVKsGAAAAAAAAAA==",
    "_self": "dbs/pEMIAA==/colls/pEMIAOfzVKs=/docs/pEMIAOfzVKsGAAAAAAAAAA==/",
    "_etag": "\"70013c95-0000-0700-0000-65f090d80000\"",
    "_attachments": "attachments/",
    "_ts": 1710264536
}
```

</details>
<br/>

##### Note about the purpose of the cost center customer document

- The presence of this document ensures that rollups happen against the cost center, so the [usage](https://github.com/enterprises/avocado-corp/billing/usage?period=3&group=0&customer=f2d443f1-a76b-4afc-84a2-ac9dc7736a01) page on the UI can show usage incurred by the resources in the cost center.
- Also emission happen for each customer document, so a cost center can be treated as a customer and [emissions](https://admin.github.com/stafftools/enterprises/avacado-corp/billing/invoices) can happen per cost center (link to avacodo corp) and also for the parent enterprise.

When looking at usage or roll ups for cost centers, the cost center UUID will be used as the customerId. For example, here is a usage item and a roll up, where the cost center UUID is used as the customerId in the partitionKey.

<details>

<summary>Cost Center Usage Example</summary>

```json
{
    "partitionKey": "60843be9-ce0a-450d-97b0-2131c134cbc3:2023:8:1:14",
    "id": "901b6f11-db0f-4829-8069-6f24d0b3d7d0",
    "BilledAmount": 6400000000,
    "Quantity": 100000000000,
    "AppliedCostPerQuantity": 64000000,
    "FractionalQuantity": 0,
    "Pricing": {
        "partitionKey": "pricing",
        "id": "actions_linux_16_core",
        "Price": 64000000,
        "Product": "actions",
        "Sku": "actions_linux_16_core",
        "MeterType": 0,
        "FriendlyName": "Actions Linux 16-core",
        "AzureMeterId": "7491f9fb-14d8-54e8-9555-ca65d39c0883",
        "EffectiveDatePrices": [],
        "FreeForPublicRepos": false,
        "EffectiveAt": 1689366600
    },
    "EntityDetail": {
        "CustomerId": "60843be9-ce0a-450d-97b0-2131c134cbc3",
        "OrganizationId": 4,
        "RepositoryId": 1,
        "ActorId": 2,
        "CostCenterDetail": {
            "EnterpriseCustomerId": "1",
            "CostCenterUUID": "60843be9-ce0a-450d-97b0-2131c134cbc3",
            "IsCostCenterProxy": true
        }
    },
    "SourceUri": "git://run/id",
    "UsageAt": 1690899555059,
    "_rid": "6DsRAPnzhaFlAAAAAAAAAA==",
    "_self": "dbs/6DsRAA==/colls/6DsRAPnzhaE=/docs/6DsRAPnzhaFlAAAAAAAAAA==/",
    "_etag": "\"0d006a12-0000-0700-0000-64c914630000\"",
    "_attachments": "attachments/",
    "_ts": 1690899555
}
```

</details>

<details>

<summary>Cost Center Monthly Usage Roll Up Example</summary>

```json
{
    "partitionKey": "60843be9-ce0a-450d-97b0-2131c134cbc3:2023:8",
    "id": "total",
    "BilledAmount": 19521900000000,
    "Quantity": 7600000000000,
    "AppliedCostPerQuantity": 49000000000,
    "FractionalQuantity": 0,
    "IsTotal": true,
    "_rid": "6DsRAPnzhaESAAAAAAAAAA==",
    "_self": "dbs/6DsRAA==/colls/6DsRAPnzhaE=/docs/6DsRAPnzhaESAAAAAAAAAA==/",
    "_etag": "\"0d0021c2-0000-0700-0000-64c9152b0000\"",
    "_attachments": "attachments/",
    "_ts": 1690899755
}
```

</details>

##### What is the Customer.IsCostCenterProxy field ?

For all the cost centers for a customer, we create a `customer:<cost center uuid>` partition similar to a regular customer's `customer:<customer id>` partition. To identify an enterprise customer vs a cost center , we use this field.

For instance for avacado corp, if it has 37 cost centers the below query would returned 37 customer records with `partitionKey = “customer:<costcenter uuids>"`

```sql
SELECT * FROM c where c.IsCostCenterProxy = true and c.EnterpriseCustomerId = "1061737"
```

Since we share the "Customer" schema, the enterprise customer’s record would have this field set to false. A cost center's customer is the parent enterprise "regular" customer record. So, if you look at the Costcenter.Customer.IsCostCenterProxy field, it will be always false.

- This implies, each cost center can have their own emission target. We use this right now only for enterprises on Azure subscription. If a different Azure subscription is set on the cost center customer proxy, it is used for emission, else the enterprise's Azure subscription id is used.

### Relevant models

Most schemas related to cost centers can be found throughout [this file](https://github.com/github/billing-platform/blob/main/lib/models/costCenter.go). Some of the key ones are listed below.

- [Cost Center](https://github.com/github/billing-platform/blob/main/lib/models/costCenter.go#L51)
- [Cost Center Key](https://github.com/github/billing-platform/blob/main/lib/models/costCenter.go#L43)
- [Cost Center Type](https://github.com/github/billing-platform/blob/main/lib/models/costCenter.go#L10)
- [Resource](https://github.com/github/billing-platform/blob/main/lib/models/resource.go#L51)
- [Resource Type](https://github.com/github/billing-platform/blob/main/lib/models/resource.go#L9)

### Queries

To find all cost centers for a given customer, use the below query in Cosmos DB Data Explorer.

```sql
SELECT * FROM c
WHERE c.partitionKey = "customer:<customerId>:costCenters"
```

This will return the cost center document, cost center resource lookup documents and the target type document for all cost centers within the enterprise.

To find a specific cost center when you know the uuid, you can look it up with this query:

```sql
SELECT * FROM c
WHERE c.partitionKey = "customer:<customerId>:costCenters" AND c.id = "<costCenterUUID>"
```

### API

There are several cost center related API endpoints, which can be found in [this file](https://github.com/github/billing-platform/blob/main/lib/api/costCenter.go). Some of the most commonly used ones include:

* [GetAllCostCenters](https://github.com/github/billing-platform/blob/main/lib/api/costCenter.go#L29)
* [GetCostCenter](https://github.com/github/billing-platform/blob/main/lib/api/costCenter.go#L47)
* [CreateCostCenter](https://github.com/github/billing-platform/blob/main/lib/api/costCenter.go#L65)
* [UpdateCostCenter](https://github.com/github/billing-platform/blob/main/lib/api/costCenter.go#L100)
* [ArchiveCostCenter](https://github.com/github/billing-platform/blob/main/lib/api/costCenter.go#L224)

### UI

The UI related code for cost centers is within the [React billing-app](https://github.com/github/github/tree/master/ui/packages/billing-app). There is a [dotcom Rails controller](https://github.com/github/github/blob/master/app/controllers/businesses/billing/cost_centers_controller.rb) that handles requests from the React app and subsequently makes requests to the appropriate billing-platform endpoints.

You can view the cost centers UI by visiting this page for any enterprise account that you're an admin of: `/{enterprise-name}/billing/cost_centers`.

Avocado Corp's cost centers page can be viewed [here](https://github.com/enterprises/avocado-corp/billing/cost_centers). If you're not an admin of Avocado Corp., reach out in [#billing-eng](https://github-grid.enterprise.slack.com/archives/GDDBJ3D45) to request access and someone from the team will add you.

## References

- [E2E code walk though for cost center creation](https://github.rewatch.com/video/mhfkh6gq6rw09lw1-billing-platform-cost-center-creation-e2e-flow).
- Original [billing platform epic](https://github.com/github/gitcoin/issues/10316) for context.
- Initial [cost center batches](https://github.com/github/gitcoin/issues/11015).
- [ADR: Cost center edit delete](https://github.com/github/gitcoin/tree/main/docs/technical/architecture-decision-record/0044-costcenter-edit-delete.md)
- [Edit delete costcenters epic](https://github.com/github/gitcoin/issues/11212).
- [Video](https://github.rewatch.com/video/n7x55h8tzdg4pwka-cc_document_setup) showing the costcenter document setup.
