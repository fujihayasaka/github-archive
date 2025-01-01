# Decision On Relational vs Non Relational Datastore for Larger Runner Supported Images

## Status
Accepted

## Context

This is a second ADR investigating the possibility of using `MySQL` (relational db) in a `Vitess or GC2` cluster over `Azure Cosmos DB for NoSQL` (non relational) for providing supported Custom, Curated & Marketplace images in our new IMS service.

[See the first ADR](./2023-08-datastore-design.md) - for how we could construct our data model in a non-relational way using Cosmos. 

## Proposal

### Proposal 1 Choosing a non relational or relational DB

#### 👍/👎 Of MySQL & Azure Cosmos DB for NoSQL

|  | Cosmos DB for NoSQL  | MySQL |
|---|---|---|
| Data Model | -👍 We have shown that supplying supported images can be achieved non relationally<br>-👍 Flexibility in storing both structured and semi structured data documents, modifying the structure of data is achieved via code, <br>using partial document updates or transactional batch operations  <br>-👎 Flexibility does also offer the potential for mistakes/errors when extending/modifying the document structure<br>-👎 The data model does need to be thought about and planned more carefully, there is an element of <br>predicted/pre calculating use cases to adopt the model for read vs write cases | -👍 The data also lends itself to Key/Value  <br>-👍 Data is store in a structured manner, intent/use is clear<br>-👍 Referential integrity <br>-👎 Schema changes require both a database and API deploy using migration scripts, <br>it's a several stage process requiring versioning  |
| Familiarity  | -👍 Cosmos DB is used by several teams across github with a paved path for the NoSQL API flavour<br>-👎 The actions/hosted-compute space is of yet to adopt it so troubleshooting is going to be less specific to our particular needs <br>-👎 Thinking of our data as self contained entities rather than relational is quite a mental paradigm shift for a company/team with heavy knowledge of relational DB's.  | -👍 MySQL & MSSQL are heavily used across dotcom and compute, there's tons of support for us  <br>-👍 We have tons of examples of tables, sproc, indices etc.. in our code base  |
| Querying | -👍 Auto-indexing, by default every property is indexed and range indexes are enforced<br>-👍 Supports multiple API's <br>-👍 Supports multiple languages out of the box, no ORM layers (object relational mapping)<br>-👍 Supports SQL, Sprocs (written in java script) & trigger functions<br>-👎 Underlying execution strategy is different and therefore harder to compare with our existing SQL query plans | -👍 Standard querying practices we're all used too |
| Development/testing | -👍 Option to use the emulator in codespace as well as per dev containers in Azure CosmosDB (by prefix-ing containers with codespace-id or branch name) <br>-👎 No native support for M1/M2 macs  | -👍 [Far better documentation on setting up](https://thehub.github.com/epd/engineering/dev-practicals/mysql/vitess/) |
| Infrastructure | -👍 Choice of multiple consistency levels allows us to balance speed and consistency<br>-👍 [Existing terraform scripts for codespace](https://github.com/github/CosmosDB/tree/main/paved-path/automation)<br>-👎 Less mature, released 2014<br>-👎 No offering for hybrid/on prem cloud solutions. Exists in Microsofts DC's. <br><br><br>   | -👍 MySQL is a mature, stable and well tested DB engine<br>-👍 Vitess can run either self-hosted, in the public cloud or in Kubernetes <br>-👍 Vitess offers eventual consistency across shards and immediate consistency within a shard<br>-👍 Guides are available for setting up a new MySQL database at GitHub, including via a Slack chatop<br> |
| Monitoring | -👍 Can set up datadog dashoards, [see example here](https://app.datadoghq.com/s/59fe6c40c/xwb-c9z-5r9) | - 👍 [DataDog dashboards with Vitess](https://github.com/github/hosted-compute-ims/pull/8#:~:text=DataDog%20dashboards%20with%20Vitess) |
| Operational Overhead | -👍 Autoscaling, local and geo redundancy is managed for us<br>-👍 On its own Cosmos is more expensive but is cheaper than vertical scaling required for VM's running MySQL Server<br>-👍 Automatic DB backups taken at regular intervals and configurable in the portal  | -👍 Vitess is a database clustering system for horizontal scaling of MySQL, <br>with automatic sharding (our queries will be agnostic to data distribution) |
| Scalability/achieving 4-9's  | -👍 CAP theorem, high availability and partition tolerance but not consistency <br>-👍 99.999% read and write availability all around the world.<br>- 👍 The IMS is a perfect candidate for adopting a new technology (we shouldn't use new for the sake of it...) <br>but if there is an appetite moving forward in hosted-compute to adopt Cosmos NoSQL DB our team will have the knowledge <br>and experience to have 'dog-fooded' it first in a scenario where the data set is small with minimal complexity. It's a production POC!<br>-👎 Theres a lot of waste in cosmos when storing high cardinality of small items, we leverage its capabilities better when our documents are more bloated,<br>in this particular instance our data is both small with small cardinality so we won't be tapping into its potential<br>-👎 Our IMS is unlikely to benefit from the gains seen with larger data sets over MySQL. For our specific use case we're looking at probably only one DB with 3 containers each with one physical partition | -👍 CAP theorem, consistency and availability but not partition tolerance <br>-👎 Sharding increases operational overhead, joins and transactions result in performance penalties in sharded deployments |


### In Summary -  Use MySQL relational database (over CosmosDB) 

As per this flowchat our data type meets both `document` and `relational` without a GHES requirment meaning both Cosmos and MySQL are options. 

![image](https://github.com/github/hosted-compute-ims/assets/88484921/bcfd19d2-1330-4ce9-a2a8-f3a0dad73dfd)

However....

- Relational is more familiar to us and intuitive without a specific knowledge requirments
- A relational DB ensures referential integrity over managing this in the data access layer
- MySQL is the largest internal service at Github, and [GH is moving towards MySQL as a service](https://thehub.github.com/epd/engineering/dev-practicals/mysql/mysql-as-service/)
- Operational overhead will be more significant in the MySQL case (for either cluster decision) however due to its already wide use the documentation surrounding set up is expansive
  -  [The Hub - MySQL at Github Overview](https://thehub.github.com/epd/engineering/dev-practicals/mysql/mysql-at-github-overview/)
  -  [Database infrastructure team - MySQL Playbooks](https://github.com/github/database-infrastructure/tree/main/docs/mysql/playbooks)
- The lack of our data complexity is more suited to a non relational db however our data size and and availavility needs mean we won't be specifically relying on Cosmos' unique features such as multi region replication or multi region write therefore perhaps Cosmos is overkill
- Both Cosmos DB and a new IMS MySQL cluster present a new opportunity for the team to learn and grow, however there does not seem as much appetite/appropriate use cases in the hosted-compute architecture for Cosmos DB, therefore we might be on a bit of island, with anything we do learn perhaps not being applicable to the long term goals of the 4-9's architecture   

### Proposal 2 Choosing a MySQL cluster - Vitess vs GitHub-managed VM infrastructure (GC2)

### In Summary -  Use MySQL on GC2

- Both MySQL Vitess and GC2 clusters are known and paved paths at Github. Documentation is wide for both.
  -  [Database infrastructure team - Docs/Vitess](https://github.com/github/database-infrastructure/tree/main/docs/vitess)
  -  [The Hub - Dev Practice MySQL Vitess](https://thehub.github.com/epd/engineering/dev-practicals/mysql/vitess/)
- As per the [Data Service Guidelines](https://thehub.github.com/epd/engineering/dev-practicals/data-services-guidelines/#data-storage-selection) MySQL is appropriate for our use case where our relational data < 2 TB. New SQL clusters with Vitess need LT approval 
- In using Vitess we would need to understand and prepare both `VSchemas` and `MySQL` schemas which come with a learning curve, although 
- Vitess' biggest limitation is cross-shard transactions. We need to ensure that we have a clear cut sharding key - particularly for the use case of Custom images, although well documented at Github (in the dotcom space) sharding is incredibly complex and the ramp up here is considerable
- Vitess does take care of failover/scalability (not in as automatic a manner as Cosmos). But setting up replicas/back up's and failovers is a familiar and well documented process in GC2. 

### Next Steps

- Reach out to the `database-infrastructure` team to confirm a [MySQL Cluster - single-primary](https://thehub.github.com/epd/engineering/dev-practicals/data-services-guidelines/?reloaded=true#mysql-cluster-single-primary) is appropriate and for initial cluster set up. 
- Start looking at [SQL Github Initial Overview](https://thehub.github.com/epd/engineering/dev-practicals/mysql/mysql-at-github-overview/)
- Start writing schemas 

## Decision 

Following a recent ADR review meeting. The team came to the consensus that a MySQL DB on Github-managed VM infrastructure (GC2) would meets our needs in terms of both data modelling and future scalbility requirements.   
