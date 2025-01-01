# Use Cosmos DB Datastore for Larger Runner Supported Images

## Status
Rejected in favour of using a relational DB (MySQL) [see ADR](./2023-08-datastore-decision-mysql.md)

***

## Context

In the 4-9's architecture our new ImageManagementService (IMS) will be responsible for `Image Promotion`, `Image Management` and `Deployment Plans`. This ADR is concerned with the design of the datastore of the `Image Management` portion of this service. Specifically how we will provide the list of supported `Curated`, `Custom` and `Marketplace` images such that we have a single source of truth which we can update without the need for a deploy.

These `Internal Images` will be owned and the responsibility of compute-flex, and therefore will exist within their own database. Only the IMS will interact with it.

Therefore we have a choice over what datastore we use, in keeping with the 4-9's architecture we should use `Cosmos DB`, this ADR will document why Cosmos DB is suitable for this use case as well as providing a proposed data model.

In using Cosmos DB over traditional relational database management systems (RDBMS) modelling of the data is paramount to achieving performant read and writes due and therefore the data model must be considered in the context of expected data access patterns.

## Proposal

### Azure Cosmos DB as our datastore

- 👍 99.999% availability [see key SLA's here](https://learn.microsoft.com/en-us/azure/cosmos-db/high-availability#slas)
- 👍 Distributed DB with multi-region availability
    - read/writing from local replicas (providing local redundancy)
    - configurable replication to all regions associated with a CosmosDB account (geo redundancy), available in all regions azure is available
- 👍 Horizontal/fan out scaling
    - Load management handled via queues and async processing
- 👎 Unfamiliar DB to the team
- 👎 In designing the model we are required to precalculate our data ahead of time to benefit from fast point reads
    - Close attention must be paid to data modeling in terms of using embedding or referencing to balance read/write performance and we perhaps don't have enough information surrounding this yet, the data model is likely to change throughout the lifecycle of implementation beyond what this ADR can predict
- 👎 Tweaking/more investigation needed to determine provisioned throughput


### Cosmos DB NoSQL as our API flavour

Cosmos DB provides multiple database APIs, we propose NoSQL

- 👍 Cosmos DB NoSQL API is native to Azure Cosmos DB, new features to Cosmos DB will be rolled out to NoSQL accounts first
- 👍 NoSQL accounts allows us to query our data using SQL which we are familiar with
- 👍 It is the paved path and recommend flavour by Github teams already using Cosmos DB, [see Github Cosmos DB API paved path](https://github.com/github/CosmosDB/blob/main/README.md#cosmos-db-api-flavors)
- 👍 Supported SDK client libraries include languages we already use, Go & C#
- 👍 We can use store procedures (Sprocs), user-defined functions and triggers like we already use in our RDMS MSSQL
- 👍 Provides a document data model, gives us more flexibility over unifying Curated, Custom and Marketplace images
- 👎 Document model means data integrity cannot be ensured at the DB level, this must be done in data access layer
- 👎 The underlying SQL execution strategy will be different to RDBMS and will require iterations of the data model/learning to get it right

***
### Data Modelling - Account, Database and Container Structure

We should use a separate container for each of our managed images

- 👍 We can control throughput at the container level allowing us to balance read/write demands based on image type
- 👍 Although images share properties there are too many differences in read/writing that mean we shouldn't aim to unify this model structure, it overcomplicates maintenance
- 👍 Items in a container are logically partitioned using a unique property from the document itself and this will different per image source (Curated/Custom/Marketplace)
- 👎 For Dotcom's list of supported images these items are typically queried together meaning we will need to read from each container and combine in the data access layer, cross container queries have higher latency

![structure](https://github.com/github/hosted-compute-ims/assets/88484921/5aec4c43-f1f4-48bb-ae4f-889b0bcd9ddb)

#### Data Modelling - Document/Item Auto Generated Fields

On uploading a document/item to Azure Cosmos NoSQL DB we get a number of auto generated fields we can use in subsequent queries.
- [See Cosmos DB Properties of an Item](https://learn.microsoft.com/en-us/azure/cosmos-db/resource-model#properties-of-an-item) when accessing via the NoSQL API.

Additionally these properties are useful on a REST API query.
- [See REST API - properties of a document](https://learn.microsoft.com/en-us/rest/api/cosmos-db/documents).

```json
{
    "_rid": "hUJWAJA7khwEAAAAAAAAAA==",
    "_self": "dbs/hUJWAA==/colls/hUJWAJA7khw=/docs/hUJWAJA7khwEAAAAAAAAAA==/",
    "_etag": "\"42004645-0000-0200-0000-64d65b010000\"",
    "_attachments": "attachments/",
    "_ts": 1691769601
}
```

***
### Data Modelling - Curated Images

***

#### Storing ImageDefinition and ImageVersion documents in the same container

> **Note** 📓
>
> This assumes we want to use a referencing approach and separate the concept of versions and definitions into different documents
> Other options and the 👍/👎 of this approach are discussed further down this document, including embedding `ImageVersions` within an `ImageDefinition` document

- 👍 Storing both ImageDefinition and ImageVersion documents in the same container as these are queried together, Cosmos DB advice is to always organise data with respect to how it is accessed and `ImageVersions` are always associated with an `ImageDefinition`.
- 👍 If want to grab both a specific `ImageVersion` and `ImageDefinition` at the same time we can access this in one request, a query to multiple containers is more costly with more latency
- 👍 An `ImageVersion` document naturally shares an associated `ImageId` with an `ImageDefinition`, this allows us to partition on `ImageId` within that container, which means each logical partition within that Curated Images container contains one curated image and all the associated image versions.

**Creating an ImageDefinition and ImageVersion index for this shared container**

**An item/document index** is comprised of a **partition key and ID**. This combination will be used to uniquely identify items within a container. The ID is used by Cosmos to locate a specific item within a logical partition, therefore we should use something meaningful to us and the API over the Cosmos auto generated ID. Otherwise we'd need some way of keeping track of generated ID's as well.

Partition keys are specified when creating a collection, if we do not provide one the collection will be limited to 10gb of data.

- Partition Key `ImageId` - such as `Ubuntu22`/`Ubuntu16`
    - The `ImageId` is naturally shared between an `ImageVersion` and `ImageDocument` it also represent the definition ID's as known to dotcom, azure and runner
- The ID, this is a string and can be alpha numeric but must not exceed 255 characters
    - For `ImageVersions` it feels natural to use the version number itself such as `1.0.1`/`1.0.2` etc.. as we know this is fixed and unchanging. It also allows us to query for a specific image version for an `ImageId` using a point read (the most efficient way of accessing data using 1 RU)
    - For `ImageDefinitions` this is less obvious it should be meaningful and fixed, maybe the `imageId` again? ....????

Auto generated ID's look similar to `"aa83df18-2098-4f7f-a87f-b53a811e3698"`

> **Note** 📓
>
> Each logical partition has a limit of 20gb. In storing ImageDefinition and ImageVersion documents in the same container we're still well within this limit. If we take the likely payload size of representing an image and image version, this is likely to be <= 2kb. Additionally we restrict the number of image versions per image to ~20-30. Should this limit ever change we're still looking at needing >=10.5 million image versions to exceed this limit.

- 👎 In storing multiple document types in the same container we need to differentiate our documents somehow, we can use a `type` field
    - Really don't think this is an issue as getting versions in the same logical partition outweigh having additional logic in the data access layer, queries that need to consult all physical partitions need higher latency, and can consume higher RUs. Additionally we can write a stored procedure we obfuscates looking for a particular document type.

#### Embedding within the Image Definition Document

- 👍 Optimise for the read case using embedding of azure properties. We will read these properties from an `ImageDefinition` when we wish to create an new `ImageVersion`
- 👍 Maintenance/synchronization between these properties across image definitions is not an issue as we should never be changing image location in azure
- 👍 Using a meaningful ID such as `Ubuntu22` means we can do a point read for a particular image definition.
- 👎 On visual inspection `id` == `imageId` is perhaps confusing

```yaml

// Image Definition Documents:

{
    "id": "Ubuntu22",
    "imageId": "Ubuntu22",  // <- Logical Partition A 
    "type": "ImageDefinition",
    "displayName": "22.04",
    "platform": "linux-x64",
    "enabled": true,
    "azureProperties": {
        "subscriptionId": "4a36dde3-dba9-4a3b-a195-c45d5d0b3ba1",
        "resourceGroupName": "mmsimagebuild",
        "galleryName": "mmssharedimagegallery"
    }
}

{
    "id": "Ubuntu16",
    "imageId": "Ubuntu16", // <- Logical Partition B
    "type": "ImageDefinition",
    "displayName": "16.04",
    "platform": "linux-x64",
    "enabled": false,
    "azureProperties": {
        "subscriptionId": "4a36dde3-dba9-4a3b-a195-c45d5d0b3ba1",
        "resourceGroupName": "mmsimagebuild",
        "galleryName": "mmssharedimagegallery"
    }
}

{
    "id": "WindowsServer2022",
    "imageId": "WindowsServer2022", // <- Logical Partition C
    "type": "ImageDefinition",
    "displayName": "2022",
    "platform": "winx-x64",
    "enabled": true,
    "azureProperties": {
        "subscriptionId": "4a36dde3-dba9-4a3b-a195-c45d5d0b3ba1",
        "resourceGroupName": "mmsimagebuild",
        "galleryName": "mmssharedimagegallery"
    }
}

```
**Handling `WindowsLatest` and `UbuntuLatest`**

Currently in our [CuratedImagesService](https://github.com/github/actions-dotnet/blob/393c514ed61eac2d0929400020d3e77bea83d64d/Runner/Service/Server/Images/CuratedImagesService.cs#L29) `UbuntuLatest` and `WindowsLatest` are pointers to existed Curated imageId's. The [CuratedLatestImage](https://github.com/github/actions-dotnet/blob/393c514ed61eac2d0929400020d3e77bea83d64d/Runner/Service/Server/Images/CuratedLatestImage.cs#L7C1-L7C1) object itself only differs in display name e.g. `Latest (2022)`

These were originally added in the Larger Runner service to align how MMS resolves runs-on `ubuntu-latest` with a latest tagged image

Propose we don't store these in the db
- Resolving UbuntuLatest and WindowsLatest should be the functionality of deployment plans and GCAS (Global capacity allocation service) rather than our image definitions table.
- [Image-gen is exploring the idea](https://github.com/github/c2c-actions-akvelon/issues/28) of changing the deployment cadence for `ubuntu-latest` vs `ubuntu-22` and therefore some pointers won't be available soon.

***
#### Using referencing for ImageVersion documents

[See Microsoft docs on when to reference](https://learn.microsoft.com/en-us/azure/cosmos-db/nosql/modeling-data#when-to-reference)

**What are the 👍/👎 of embedding...**

Embedding `ImageVersion`s within an `ImageDefinition` would look like something similar to this

```yaml
{
    "imageId": "Ubuntu22",
    "displayName": "22.04",
    "platform": "linux-x64",
    "enabled": true,
    "azureProperties": {
        "subscriptionId": "4a36dde3-dba9-4a3b-a195-c45d5d0b3ba1",
        "resourceGroupName": "mmsimagebuild",
        "galleryName": "mmssharedimagegallery"
    },
    "imageVersions": [
        { "id": "1.0.1", "enabled": true, "promoted": true},
        { "id": "1.1.0", "enabled": true, "promoted": true},
        { "id": "1.2.1", "enabled": false, "promoted": true},
        { "id": "1.0.1", "enabled": false, "promoted": true} // <- There is no way in the db to ensure ID's are unique in this approach
    ]
}
```
- 👍 In a single read for `Ubuntu22` we get all image versions
- 👍 Arrays are encoded with the index of the item as an intermediate node so it would be an index seek to find a specific image version (most efficient evaluation of query filter)
- 👎 There is no concept of key constraints in a non relational db, i.e. there's no protection at the db level of two entries in ImageVersions having the same id, this protection would need to occur at the data access/server level when writing to the db
- 👎 To get a specific image version we'd need to perform a self join within the document in an SQL query (could also do at the data access level) and this requires an array iteration
- 👎 An update to an image version means reading the whole document in order to insert or modify a version in an array (more RU's)
- 👎 The document itself could grow as image versions are released, typically the advise is not to embed when your embedded data changes frequently, most operations will become slower and more expensive as documents grow in size due to reading the whole document and attempt to iterate to find the correct array item to modify

**What are 👍/👎 to referencing....**

- 👍 Allows us to update (enabled/disable/promote etc) an `ImageVersion` without modifying the associated `ImageDefinition`.
- 👍 Indices for items are formed from partition key and id, here the index for each our items is the `ImageVersion` (e.g. 1.0.0, 1.0.1) and `ImageId` (e.g. `Ubuntu22`)
    - We won't have the scenario where we have the same version for the same imageId so we can can be sure this combination is unique
    - It also allows us to do a point read for an exact `ImageVersion` and `ImageId`
- 👍 Means we won't worry about document size only logical partition size where we have better control over management, it will be much harder to un-embed this data if we find our scale means our document size becomes unruly

```yaml

Image Versions Documents:

{
    "id": "1.0.1",
    "type": "ImageVersion",
    "imageId": "Ubuntu22", // <- Logical Partition A 
    "enabled": true,
    "promoted": true,
    "azureProperties": {
        "subscriptionId": "4a36dde3-dba9-4a3b-a195-c45d5d0b3ba1",
        "resourceGroupName": "mmsimagebuild",
        "galleryName": "mmssharedimagegallery"
    }
}

{
    "id": "1.1.0",
    "type": "ImageVersion",
    "imageId": "Ubuntu22", // <- Logical Partition A
    "enabled": true,
    "promoted": true,
    "azureProperties": {
        "subscriptionId": "4a36dde3-dba9-4a3b-a195-c45d5d0b3ba1",
        "resourceGroupName": "mmsimagebuild",
        "galleryName": "mmssharedimagegallery"
    } 
}

{
    "id": "1.1.0",
    "type": "ImageVersion",
    "imageId": "WindowsServer2022", // <- Logical Partition C
    "enabled": false,
    "promoted": true,
    "azureProperties": {
        "subscriptionId": "4a36dde3-dba9-4a3b-a195-c45d5d0b3ba1",
        "resourceGroupName": "mmsimagebuild",
        "galleryName": "mmssharedimagegallery"
    }
}

{
    "id": "1.1.0",
    "type": "ImageVersion",
    "imageId": "Ubuntu16", // <- Logical Partition B
    "enabled": false,
    "promoted": true,
    "azureProperties": {
        "subscriptionId": "4a36dde3-dba9-4a3b-a195-c45d5d0b3ba1",
        "resourceGroupName": "mmsimagebuild",
        "galleryName": "mmssharedimagegallery"
    }
}

```

**Storing `ImageVersion` `latest` in the db...**

- `Latest` is not returned in `ListImageVersions` for Curated images and is not used in dotcom api calls
- It will be represented in our shared redis service and calculated in flight

**Duplicating/embedding `azureProperties` in both `ImageDefinition` and `ImageVersion` documents**

- We will read these properties from an `ImageDefinition` when we wish to create an new `ImageVersion`
- When creating an `ImageReference` to work with a particular image we will read this from an `ImageVersion`
- Maintenance/synchornization between these properties is not an issue as we should never be changing image location in azure


#### With this Curated Image data model what could our SQL look like?

**ListCuratedImages**

```sql
SELECT * FROM curated WHERE curated.type = 'ImageDefinition'
```

- The query here is not using the `partiton key of imageId` as a filter, therefore this has the potential to be a cross partition query (consulting multiple physical partitions)
- One physical partition stores 50gb of data with each logical partition holding 20GB
- Logical partitions are unlimited, but physical partitions are added when either the combination of logical exceeds > 50gb or throughput to the physical partition > 10,000 request units per second
- With each of our logical partitions storing one `ImageDefinition` and all associated `ImageVersion` the calculations are as follows
    - 1 `ImageDefinition` document ~ 485 bytes (call it 2kb)
    - 1 `ImageVersion` document ~ 450 bytes (call it 2kb)
    - 20 GB / 2 KB = 10.5 millions of image versions to fill one logical partition (and we currently restrict to 20-30, gives us a wide birth..)
    - Assuming one logical partition is a definition of 2Kb + 1000 image version versions of 2kb then each logical partition ~ 2002 kb we'd therefore need (50gb/2002kb) ~ 25,000 curated images to fill a physical partition

**In summary with this model and above query we're still looking at one physical partition and therefore still in-partition queries**

<details>
    <summary>List all curated images response</summary>

```yaml
[
    {
        "id": "Ubuntu22",
        "imageId": "Ubuntu22",
        "type": "ImageDefinition",
        "displayName": "22.04",
        "platform": "linux-x64",
        "enabled": true,
        "azureProperties": {
            "subscriptionId": "4a36dde3-dba9-4a3b-a195-c45d5d0b3ba1",
            "resourceGroupName": "mmsimagebuild",
            "galleryName": "mmssharedimagegallery"
        },
        "_rid": "hUJWAJA7khwBAAAAAAAAAA==",
        "_self": "dbs/hUJWAA==/colls/hUJWAJA7khw=/docs/hUJWAJA7khwBAAAAAAAAAA==/",
        "_etag": "\"12000d63-0000-0200-0000-64df7fa20000\"",
        "_attachments": "attachments/",
        "_ts": 1692368802
    },
    {
        "id": "Ubuntu16",
        "imageId": "Ubuntu16",
        "type": "ImageDefinition",
        "displayName": "16.04",
        "platform": "linux-x64",
        "enabled": false,
        "azureProperties": {
            "subscriptionId": "4a36dde3-dba9-4a3b-a195-c45d5d0b3ba1",
            "resourceGroupName": "mmsimagebuild",
            "galleryName": "mmssharedimagegallery"
        },
        "_rid": "hUJWAJA7khwDAAAAAAAAAA==",
        "_self": "dbs/hUJWAA==/colls/hUJWAJA7khw=/docs/hUJWAJA7khwDAAAAAAAAAA==/",
        "_etag": "\"1200f264-0000-0200-0000-64df7fac0000\"",
        "_attachments": "attachments/",
        "_ts": 1692368812
    },
    {
        "id": "WindowsServer2022",
        "imageId": "WindowsServer2022",
        "type": "ImageDefinition",
        "displayName": "2022",
        "platform": "winx-x64",
        "enabled": true,
        "azureProperties": {
            "subscriptionId": "4a36dde3-dba9-4a3b-a195-c45d5d0b3ba1",
            "resourceGroupName": "mmsimagebuild",
            "galleryName": "mmssharedimagegallery"
        },
        "_rid": "hUJWAJA7khwEAAAAAAAAAA==",
        "_self": "dbs/hUJWAA==/colls/hUJWAJA7khw=/docs/hUJWAJA7khwEAAAAAAAAAA==/",
        "_etag": "\"1200e589-0000-0200-0000-64df806b0000\"",
        "_attachments": "attachments/",
        "_ts": 1692369003
    }
]
```

</details>


```sql
SELECT * FROM curated WHERE curated.type = 'ImageDefinition' AND curated.enabled
```

<details>
    <summary>List all enabled curated images response</summary>

```yaml
[
    {
        "id": "Ubuntu22",
        "imageId": "Ubuntu22",
        "type": "ImageDefinition",
        "displayName": "22.04",
        "platform": "linux-x64",
        "enabled": true,
        "azureProperties": {
            "subscriptionId": "4a36dde3-dba9-4a3b-a195-c45d5d0b3ba1",
            "resourceGroupName": "mmsimagebuild",
            "galleryName": "mmssharedimagegallery"
        },
        "_rid": "hUJWAJA7khwBAAAAAAAAAA==",
        "_self": "dbs/hUJWAA==/colls/hUJWAJA7khw=/docs/hUJWAJA7khwBAAAAAAAAAA==/",
        "_etag": "\"42002a45-0000-0200-0000-64d65ae90000\"",
        "_attachments": "attachments/",
        "_ts": 1691769577
    },
    {
        "id": "WindowsServer2022",
        "imageId": "WindowsServer2022",
        "type": "ImageDefinition",
        "displayName": "2022",
        "platform": "winx-x64",
        "enabled": true,
        "azureProperties": {
            "subscriptionId": "4a36dde3-dba9-4a3b-a195-c45d5d0b3ba1",
            "resourceGroupName": "mmsimagebuild",
            "galleryName": "mmssharedimagegallery"
        },
        "_rid": "hUJWAJA7khwEAAAAAAAAAA==",
        "_self": "dbs/hUJWAA==/colls/hUJWAJA7khw=/docs/hUJWAJA7khwEAAAAAAAAAA==/",
        "_etag": "\"42004645-0000-0200-0000-64d65b010000\"",
        "_attachments": "attachments/",
        "_ts": 1691769601
    }
]
```
</details>

***
**ListImageVersions**

```sql
SELECT * FROM curated WHERE curated.type = 'ImageVersion' AND curated.imageId = 'Ubuntu22' AND curated.enabled
```
<details>
    <summary>Get all enabled image versions for Ubuntu22</summary>

```yaml
[
    {
        "id": "1.0.1",
        "type": "ImageVersion",
        "imageId": "Ubuntu22",
        "enabled": true,
        "promoted": true,    
        "_rid": "hUJWAJA7khwGAAAAAAAAAA==",
        "_self": "dbs/hUJWAA==/colls/hUJWAJA7khw=/docs/hUJWAJA7khwGAAAAAAAAAA==/",
        "_etag": "\"42006745-0000-0200-0000-64d65b1b0000\"",
        "_attachments": "attachments/",
        "_ts": 1691769627
    },
    {
        "id": "1.1.0",
        "type": "ImageVersion",
        "imageId": "Ubuntu22",
        "enabled": true,
        "promoted": true,    
        "_rid": "hUJWAJA7khwHAAAAAAAAAA==",
        "_self": "dbs/hUJWAA==/colls/hUJWAJA7khw=/docs/hUJWAJA7khwHAAAAAAAAAA==/",
        "_etag": "\"4200a945-0000-0200-0000-64d65b470000\"",
        "_attachments": "attachments/",
        "_ts": 1691769671
    }
]
```
</details>


***
### Data Modelling - Custom Images
***

> Note
>
> This will be pretty similar to modelling of Curated Images

#### Storing Custom ImageDefinition and ImageVersion documents in the same container
- 👍 Storing both ImageDefinition and ImageVersion documents in the same container as these are queried together
- 👍 Store `ownerId` against `ImageDefinition` and `ImageVersion` documents and partition on `ownerId` means each logical partition within that Custom Images container for a single customer contains all of their custom images and image versions
- 👎 Again we need a type field of `ImageDefinition` and `ImageVersion`
    - Again I really don't think this is an issue

> Warning ⚠️
>
> Again we must be confident that a single customer's image definitions and image version documents do not exceed 20gb or we must manually repartition our data

Currently Custom image definitions are stored in the database, see [tbl_ImageDefinition](https://github.com/github/actions-dotnet/blob/caea5b404005a2abba08b47f400d00b9a85fbe32/Runner/Service/Sql/Runner/Tables/tbl_ImageDefinition.sql)

```yaml

// Image Definition Documents:

[
    {
        "id": 1, // <- This is tbl_ImageDefinition#ImageDefinitionId, generated by runner service on persistence, (INT) 1/2/3 etc..
        "ownerId": "O_kgAE",
        "type": "ImageDefinition",
        "name": "customer-custom-image",
        "osType": "Linux",
        "state": "ready", // <- `ImageDefinitionState`
        "azureProperties": {
            "subscriptionId": "4a36dde3-dba9-4a3b-a195-c45d5d0b3ba1",
            "resourceGroupName": "customerrg",
            "galleryName": "customergallery"
        }
    },
    {
        "id": 2,
        "ownerId": "O_kgAE",
        "type": "ImageDefinition",
        "displayName": "customer-custom-image",
        "osType": "Windows",
        "state": "ready",
        "azureProperties": {
            "subscriptionId": "4a36dde3-dba9-4a3b-a195-c45d5d0b3ba1",
            "resourceGroupName": "customerrg",
            "galleryName": "customergallery"
        }
    },
    {
        "id": 1,
        "ownerId": "P_kgBE",
        "type": "ImageDefinition",
        "displayName": "customer-custom-image",
        "osType": "Windows",
        "state": "ready",
        "azureProperties": {
            "subscriptionId": "4a36dde3-dba9-4a3b-a195-c45d5d0b3ba1",
            "resourceGroupName": "customerrg",
            "galleryName": "customergallery"
        }
    }
]

```

#### Referencing ImageDefinition in ImageVersion documents

- 👍 Although our customer base for custom images at the moment remains small we still should plan for the potential number of `ImageVersion`s therefore embedding this within an `ImageDefinition` is not appropriate as this could be an unbounded list and the negatives remain the same as discussed for Curated.
- 👍 Allows us to update (enabled/disable etc) an `ImageVersion` without modifying the associated `ImageDefinition`.

Currently Custom image versions are stored in the database, see [tbl_ImageVersion](https://github.com/github/actions-dotnet/blob/caea5b404005a2abba08b47f400d00b9a85fbe32/Runner/Service/Sql/Runner/Tables/tbl_ImageVersion.sql)


```yaml

// Image Version Documents:

[
    {
        "version": "1.0.1",
        "ownerId": "P_kgBE",
        "type": "ImageVersion",
        "imageDefinitionId": 1,
        "state": "ready" 
        "azureProperties": {
            "subscriptionId": "4a36dde3-dba9-4a3b-a195-c45d5d0b3ba1",
            "resourceGroupName": "customerrg",
            "galleryName": "customergallery"
            "azureBlobUri": "/blob/",
            "azureVersion": null
        }
    },
    {
        "version": "1.0.1", // <- Cannot ensure unique image version for one customer for image definition. Create an ID as a composite? 
        "ownerId": "P_kgBE",
        "type": "ImageVersion",
        "imageDefinitionId": 1,
        "state": 1,
        "azureProperties": {
            "subscriptionId": "4a36dde3-dba9-4a3b-a195-c45d5d0b3ba1",
            "resourceGroupName": "customerrg",
            "galleryName": "customergallery"
            "azureBlobUri": null, // <- Can be null or defined, both are valid in json
            "azureVersion": null
        }
    }
]
```

**Duplicating/embedding `azureProperties` in Custom `ImageVersion` documents**

- Per Custom `ImageVersion`, `azureBlobUri` and `azureVersion` are unique, but we should embed the azure properties (subscription/etc) from the corresponding `ImageDefinition`
- We will read these properties from an `ImageDefinition` when we wish to create an new `ImageVersion`
- When creating an `ImageReference` to work with a particular Custom image version we will read all these properties from an `ImageVersion`

**Composite ID for Custom `ImageVersion`**

- Indices for items are formed from partition key and id, however given our `ownerId` forms our partition key we cannot use `ImageVersion` as an ID as a customer can have version 1.0.1 for both `ImageDefinitionId` 1 and 2 therefore `ownerId:version` would not be unique
- Without using version as part of ID etc.. there's no way in the DB itself to ensure that there is only one version (1.0.1) etc for one customer for one image definition

Currently `ImageVersions` are uniquely identified in the runner service from a combination of `partitionId`, `ImageDefinition` and `version`.

e.g.

```sql
CREATE UNIQUE CLUSTERED INDEX PK_tbl_ImageVersion ON Runner.tbl_ImageVersion
(
    PartitionId,
    ImageDefinitionId,
    Version
)
```

Therefore we could create a composite ID using this information. e.g. `${version}-{imageDefinitionId}` still using owner_id as our partition key. 

```yaml
{
    "id": "1.0.2-1",
    "version": "1.0.2",
    "ownerId": "P_kgBE",
    "type": "ImageVersion",
    "imageDefinitionId": 1,
    "state": 1,
    "azureProperties": {
        "subscriptionId": "4a36dde3-dba9-4a3b-a195-c45d5d0b3ba1",
        "resourceGroupName": "customerrg",
        "galleryName": "customergallery",
        "azureBlobUri": null,
        "azureVersion": null
    },
    "_rid": "hUJWAJCSM5YGAAAAAAAAAA==",
    "_self": "dbs/hUJWAA==/colls/hUJWAJCSM5Y=/docs/hUJWAJCSM5YGAAAAAAAAAA==/",
    "_etag": "\"1900b62b-0000-0200-0000-64dfa5630000\"",
    "_attachments": "attachments/",
    "_ts": 1692378467
}

```
![image](https://github.com/github/hosted-compute-ims/assets/88484921/257e937c-c5b3-49a5-9454-1c2d8f9592f4)



- 👍 Avoid version conflict for same image definition
- 👎 Data acess layer needs to maintain integrity between ID, imageDefinitionID and version fields


### Future Discussions/Further Reading

- Configuring provisioned throughput at container/db level, [Github Azure Docs](https://github.com/MicrosoftDocs/azure-docs/blob/main/articles/cosmos-db/set-throughput.md#introduction-to-provisioned-throughput-in-azure-cosmos-db)
- [Fine tuning query performance and reading metrics](https://learn.microsoft.com/en-us/azure/cosmos-db/nosql/query-metrics)
- [Querying - working with json](https://learn.microsoft.com/en-us/azure/cosmos-db/nosql/query/working-with-json)
