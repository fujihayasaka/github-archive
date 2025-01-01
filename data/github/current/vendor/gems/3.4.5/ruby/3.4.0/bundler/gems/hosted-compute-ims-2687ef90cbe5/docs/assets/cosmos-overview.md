# An Overview of Cosmos NoSQL DB

This guide aims to give an overview of Cosmos NoSQL DB using the example of how we _might/could_ leverage it in building a data model to support Curated Images within our Image Management Service. This is not intended as design document or proposed ADR.

[Associated rewatch - Azure CosmosDB Overview - August 15, 2023](https://github.rewatch.com/video/yyrv0yct3gu57z6l-azure-cosmosdb-overview-august-15-2023)

# Image Management Service - Problem Statement

Our new `ImageManagementService` (IMS) will be responsible for `Image Promotion`, `Image Management`. The example used guide in this guide references potential design of the `Image Management` portion of this service.

_**Specifically how can Cosmos No SQL DB be used to support the uploading/updating of Curated Images for Larger Runners**_

Supported Curated images are currently hardcoded within the [CuratedImagesService](https://github.com/github/actions-dotnet/blob/main/Runner/Service/Server/Images/CuratedImagesService.cs). We wish to store this list of `Internal Images` in a database, allowing updates without the need for a deploy.

These `Internal Images` will be owned and the responsbility of compute-flex, and therefore will exist within their own database. Only the IMS will interact with it.

Therefore, we have a choice over what DB we use. Our data and data access pattern allows us to use either a non-relational or relationl approach to our data modelling.

To clarify, our IMS supported image data model will be relational using MySQL in a GH managed cluster (see this ADR [Using a Relational DB for Supported Images](https://github.com/github/hosted-compute-ims/blob/main/docs/adrs/2023-08-datastore-decision-mysql.md)).

This guide is aimed as an addendum to our rejected ADR ([Using Cosmos DB Datastore for Supported Images](https://github.com/github/hosted-compute-ims/blob/main/docs/adrs/2023-08-datastore-design.md)) to introduce Cosmos knowledge to the team but in the context of the services we work in. Otherwise I could send you straight to the labyrinth that is the Azure docs 😅 (I'm nice like that....)

Let's talk about how _we could use_ Cosmos DB for supplying our supported Curated Images in the IMS.

# Cosmos NoSQL DB - Key Concepts (A **distributed NoSQL** database)

**Non-relational & NoSQL Db's:**
- These words are often used interchangebly, in practice NoSQL means non-relational
- As opposed to using a tabular schema of rows and columns, data can be stored both semi-structured and unstructured, as a....
    - [JSON Document Store](https://learn.microsoft.com/en-us/azure/architecture/data-guide/big-data/non-relational-data#document-data-stores)
    - [Key/Value Pairs](https://learn.microsoft.com/en-us/azure/architecture/data-guide/big-data/non-relational-data#keyvalue-data-stores)
    - [Graph Data Stores - using edges and vertices](https://learn.microsoft.com/en-us/azure/architecture/data-guide/big-data/non-relational-data#graph-data-stores)
- NoSQL means that the data store does not use SQL for queries... however many db's, including Cosmos NoSQL, support SQL compatible queries, with the difference being the underlying execution strategy of these queries against traditional RDBMS such as MSSQL.

**Distributed Databases & Multi-region Availability**
- NoSQL dbs were originally designed for horizontal scaling/scaling out, that is we add more machines to our pool of resources as opposed to adding more power to an existing machine (scaling up), but these NoSQL db's would normally need extra configuration for local or geo redundancy
- As CosmosDB is a distributed Azure offering it is available in all regions Azure is available, we can read and write data from local replicas, but the data will also be replicated to all regions associated with our Azure ComosoDB account.

**API Flavours**
- In order to communicate with the DB's there are several API's to choose from
- The NoSQL API is native to CosmosDB and is the paved path here at GitHub, [see that recommendation here](https://github.com/github/CosmosDB/blob/main/README.md#cosmos-db-api-flavors)
- In the NoSQL API flavour, data is stored  `JSON Document Store`
- Despite the name NoSQL 🤦, items are queried using SQL syntax


## CosmosDB Azure Resource Concepts

CosmosDB uses quite generic terms to represent how it stores data due to the many API flavours.

![image](https://github.com/github/hosted-compute-ims/assets/88484921/98c83d34-403e-4d13-b5ea-b444ad90f87c)

- Under one `Azure subscription` we can create `50 CosmosDB Accounts`
- `1 CosmosDB Account` consists of `databases`
- A database/namespace is a logical group of `items` partitioned across `containers`
- If we want to compare this to MSSQL we can think of them as tables, but ones which are schema agnostic
- These containers are our units of 'scalability' - these are what provide our horizontal scaling capability
- In order to achieve this the container comprises physical partitions, throughput is increased by adding more physical partitions (a container is a logical grouping of resources across one or more physical partitions)
- Cosmos also has a concept of logical partitions, this is a group of items/documents with the same `PartitionKey` 
- This is typically formed from a unique property of the stored data
- In using the NoSQL native API our `container(s)` will be returned as a collection of `items`
- Where each `item` is a `json document`

## Cosmos DB - Data Modelling
- In designing our data model we must consider whether it will be read or write heavy
- Embedding data/de-normalizing is how we optimise for the read case
- In relational DB's such as MSSQL the aim is to normalize data which means for a particular entity such as a Person you break that down into components such as Address & ContactDetail, we avoid storing redundant data but refer to it instead. However at run time to de-normalize this data on a read we would need multiple joins. And to update a single Person's information we would need to write across several tables.

```SQL
SELECT p.FirstName, p.LastName, a.City, cd.Detail
FROM Person p
JOIN ContactDetail cd ON cd.PersonId = p.Id
JOIN ContactDetailType cdt ON cdt.Id = cd.TypeId
JOIN Address a ON a.PersonId = p.Id
```

- Typically, data modelling is Cosmos NoSQL DB should be optimized for the read case, meaning we should embed data when we can.
- Normalizing (referencing) data provides better write performance
- We can also choose a hybrid approach of embedding and referencing where appropriate (referencing represents a relationship, but it's not the same as a relationship such as shared id's in MSSQL)

> **Warning** ⚠️
> We cannot store different entities in different containers if they are typically queried together. They should either be embedded in those entities or stored as separate items using a shared partition key with the other entities in the same container.
> This is because data is schema free, and we cannot join data across documents/items like you would in MSSQL or another RDBMS. Joins are scoped within an item and also cannot occur across containers. [See Microsoft docs on Joins in Azure Cosmos DB](https://learn.microsoft.com/en-us/azure/cosmos-db/nosql/query/join)

## Choosing a PartitionKey and ID

In Cosmos DB, the objective is to store data in the same container when it shares the same partition key and is frequently accessed/queried together.

An items index is formed from its id and partition key, this is globally unique key for items within a container, if you have both of these values (id-partitionKey) you can perform what is called a _point read_. This is the most effcient way to read data and costs 1 RU as it doesn't use the query engine. Therefore it is important to also assign a meaningful ID.

![image](https://github.com/github/hosted-compute-ims/assets/88484921/6ffd962b-8f9e-4ea3-be7f-6f980113568a)

> **Note** 📓
> When looking at consumed RU's in the Cosmos data explorer we will always see > 1 RU even for a query that is using the ID and partition key, point reads can only be executed through the SDK's. The cosmos data explorer uses the query engine.

## Image Definition as use case for embedding

- PartitionKey is `imageId`
- Therefore, we would have two logical partitions, one for `Ubuntu22` and another for `WindowsServer2022`

```yaml
{
    "imageId": "Ubuntu22",
    "displayName": "22.04",
    "platform": "linux-x64",
    "enabled": true,
    "promoted": true,
    "azureProperties": {
        "subscriptionId": "4a36dde3-dba9-4a3b-a195-c45d5d0b3ba1",
        "resourceGroupName": "mmsimagebuild",
        "galleryName": "mmssharedimagegallery"
    }
}

{
    "imageId": "WindowsServer2022",
    "displayName": "2022",
    "platform": "winx-x64",
    "enabled": true,
    "promoted": false,
    "azureProperties": {
        "subscriptionId": "4a36dde3-dba9-4a3b-a195-c45d5d0b3ba1",
        "resourceGroupName": "mmsimagebuild",
        "galleryName": "mmssharedimagegallery"
    }
}

```

Here the duplicated or redundant data is our `azureProperties`. This means that we can retrieve a complete record for a specific image definition in single read operation. We can/should do this when the _redundant_/embedded data is always queried together and changes infrequently. However, this does mean that if these properties change and that change should be reflected in all images then we must perform multiple writes. See [Microsoft - When to embed](https://learn.microsoft.com/en-us/azure/cosmos-db/nosql/modeling-data#when-to-embed)

## Image Version as use case for referencing
**(tbh a case can be made for both embedding and referencing, but let's do a thought experiment...)**

Let's say that we wish to store all image versions for a particular image definition against that image definition...

```json
{
    "imageId": "Ubuntu22",
    "displayName": "22.04",
    "platform": "linux-x64",
    "enabled": true,
    "promoted": true,
    "azureProperties": {
        "subscriptionId": "4a36dde3-dba9-4a3b-a195-c45d5d0b3ba1",
        "resourceGroupName": "mmsimagebuild",
        "galleryName": "mmssharedimagegallery"
    },
    "imageVersions": [
        { "id": "1.0.1", "enabled": true},
        { "id": "1.1.0", "enabled": true},
        { "id": "1.2.1", "enabled": false}
    ]
}
```

- 👍 In a single read for `Ubuntu22` we get all image versions
- 👍 When using an array each item's position in the array is automatically indexed, therefore we can get a specific image version if we know
- 👎 There is no concept of key constraints in a non-relational db, i.e. there's no protection at the db level of two entries in the `imageVersions` array having the same id, this protection would need to occur at the data access/server level when writing to the db
- 👎 To get a specific image version we'd need to perform a self join within the document in an SQL query (we could also do at the data access level)

```sql
SELECT v.id, v.enabled
FROM images i
  JOIN v IN i.imageVersions
  WHERE i.imageId = 'Ubuntu22'
  AND v.id = '1.0.1'
```

Additionally, updating a single image version would mean iterating as well.

**Let's look at how we could use referencing by storing both image version and image definition documents within the same container**

```yaml
{
    "id": "1.0.1",
    "type": "ImageVersion", 
    "imageId": "Ubuntu22", // Logical Partition A
    "enabled": true
}

{
    "id": "1.1.0",
    "type": "ImageVersion",
    "imageId": "Ubuntu22", // Logical Partition A
    "enabled": true,
}
```

- The indices for these items are formed from `Id` and PartitionKey (`ImageId`)
- The `ImageId` here references the `ImageId` from our `ImageDefinitionDocuments`
- This allows us to update an image version document without reading an associated image definition
- Allows us to maintain data integrity by using the version as the ID, thereby preventing duplicate image versions for an image definition
