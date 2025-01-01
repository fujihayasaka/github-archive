# Licensify

The Licensify service is responsible for issuing and tracking licenses consumed by Customers for GitHub's license based products (SDLC/GitHub Enterprise, GitHub Advanced Security, and Copilot)

## Quick Links

- [Development](docs/development.md)
- [Monitoring](docs/monitoring.md)
- [Runbooks](docs/runbooks)

## Architecture

The Licensify service is written in Go and uses CosmosDB as the primary data store. It provides a TWIRP API for clients to create product enablements and to retrieve license information. All license generation is done asynchronously by the service subscribing to hydro events. If a specific hydro event is associated with a product enablement, the service will generate or update the relevant licenses.

For example, a Customer may enable Copilot for a Team. The product enablement is recorded in Licensify by a TWIRP request statement that Copilot has been enabled for that specific Team. Licensify subscribes to the `cp1-iad.ingest.github.v1.MembershipUpdate` topic. When an event is consumed by Licensify, it will look up the product enablements for the Team and see that Copilot has been enabled. It will then generate a Copilot License for that user.

### Event Processing

Licensify uses a few strategies to process various messages in the system. Please
reference the following docs for in-depth information of each:

1. [Hydro handlers](docs/hydro_handlers.md)
2. [Aqueduct jobs](docs/aqueduct_jobs.md)
3. [Event handlers](docs/event_handlers.md)

## Business Objects / Concepts

This section describes the business objects that Licensify is responsible for managing. The information here is provided at a high level; more information about the specific storage and structure of these objects can be found in [CosmosDB Documents](docs/cosmosdb_documents.md).

### Product Enablements

A product enablement represents the intention by the customer for a certain category of licensees to consume a license for a specific product.

A product enablement consists of a Customer, a Product, an EntityType, and a Reason. The EntityType is the model that the group of licensees is associated with while the reason describes the way the licensees are associated with the EntityType.

In the case of the SDLC product, some of the enablements are implicitly created. For example a user membership in any organization will automatically consume a licenses without the customer specifically enabling that organization. However, for Copilot, the customer would have to explicitly enable copilot for members of an organization.

Here are some illustrative examples of product enablements:

```
Customer: GitHub
Product: SDLC
EntityType: Organization
Reason: Membership
```

```
Customer: GitHub
Product: SDLC
EntityType: Repository
Reason: Collaborator
```

```
Customer: GitHub
Product: Copilot
EntityType: Team
Reason: Membership
```

```
Customer: GitHub
Product: GitHub Advanced Security
EntityType: Repository
Reason: Active Committer
```

### Customer License

A Customer License represents that a licensee is consuming a license for a specific product under a specific customer. The license is associated with a Customer, a Licensee, a Product and will contain one or more product enablements that associate back to the product enablements that contribute to the license existing.

For metered customers, the License will also contain a possible expiration date. When every product enablement has been removed, the license expiry is set to the end of the month.

Here's are some examples of Customer Licenses:

```
Customer: GitHub
Product: SDLC
Licensee:
 - Type: User
   ID: 1
ProductEnablements:
  - EntityType: Organization
    Reason: Membership
    EntityIDs: [1, 2]
  - EntityType: Repository
    Reason: Collaborator
    EntityIDs: [11, 12]
```

```
Customer: GitHub
Product: SDLC
Licensee:
 - Type: BusinessUserAccout
   ID: 99
ProductEnablements:
  - EntityType: EnterpriseServer
    Reason: Membership
    EntityIDs: [4]
```

```
Customer: GitHub
Product: GHAS
Licensee:
 - Type: User
   ID: 1
ProductEnablements:
  - EntityType: Repository
    Reason: Active Committer
    EntityIDs: [7]
```

```
Customer: GitHub
Product: GHAS
Licensee:
 - Type: User
   ID: 1
ProductEnablements: []
ExpiresAt  2024-05-31
```

### Licensee License

The Licensee License represents that a specific licensee has a license for a specific product. Whereas the Customer License is a customer centeric view into the licenses, the Licensee License is a licensee centric view into the licenses.

The Licensee License is especially important for products in which a single user could be granted a license to use the product by multiple customers, and their use of the product might need to be looked up without knowing the specific customer that granted the license.

Here are some examples of Licensee Licenses:

```
Licensee:
 - Type: User
   ID: 1
Product: Copilot
Customer: GitHub
```

```
Licensee:
 - Type: User
   ID: 1
Product: Copilot
Customer: Avocado Corp
```


