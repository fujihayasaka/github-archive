# CosmosDB state of paved path research

## Paved Path questions

### What are the current approaches to data modeling?

For data modeling there are a couple of approaches and between Gremlin (the
graph API flavour), NoSQL (the document store/KV flavour), and Cassandra (the
column store flavour) there are a couple of teams experimenting with a
variety.

For our general needs of a somewhat KV like model (i.e.
`notification_entries`) with a lot of group filtering it might make the most
sense to experiment with the Cassandra API. This one is also available
completely through [`gocql`](https://github.com/gocql/gocql) (the official
golang Cassandra client) without additional need of the Azure SDK. Even
creating collections and configuring RUs for them can be done directly through
`gocql`.

The MongoDB flavour specifically is discouraged and will likely not
be supported in the future.

### What are the tools that exist for monitoring?

All metrics that are exposed through Azure monitor are available in Datadog.
There is a top level service principal for all accounts that makes sure every
newly provisioned CosmosDB account gets included in the metrics sync.
There is also an [example Datadog dashboard for CosmosDB][dd_cosmos].

RU usage monitoring is not yet included but coming. Longer term the plan is
improve overall cost monitoring in Datadog. This needs a separate integration
to be written as that data is not available in Azure Monitor.

### What are the tools that exist for performance analysis?

Azure Monitor metrics exist for [performance monitoring and
debugging](https://learn.microsoft.com/en-us/azure/cosmos-db/cassandra/monitor-insights)
and are available in Datadog.

### What are the options for disaster recovery?

Generally databases are provisioned with regional failover replicas that are
first choice for failing over and are configured to do so automatically.
Manual failover can be configured but is not recommended since it requires all
participating regions to be healthy.

Backups are done periodically and stored for up to 30 days. Restoring from
them should be a last resort since it's fairly cumbersome. A support ticket
needs to be opened which will result into data being restored into a new
read-only account from which instances can initiate a data sync.

More details are available [on the paved path repo][paved_path_backups].

### What are the costs of running CosmosDB?

The costs are generally comprised of provisioned RUs ([Request Units, a
CosmosDB cost abstraction][RUs]) for reads and writes, where generally for
more requests we need to pay for more RUs. The other dimension is storage for
primaries, replicas, and backups. Generally the cost is not exceeding what
we generally pay for a Vitess sharded cluster of similar size.


### What is the expected response time on support?

Response time is generally fairly quick even for non-incident questions. The
CosmosDB team is reachable on MS Teams and often happy to help out with
questions.

### What does it take to provision/bootstrap CosmosDB?

Provisioning of CosmosDB is generally done via a paved path terraform module.
The idea here is that terraform just takes care of the basics like
provisioning the actual account, database, set up the service principal, and
configure backup and replication as well as access control patterns.

All schema and data modelling changes should then be done via application side
similar to migrations in MySQL land.

More information is available [on the paved path repo][paved_path_terraform].

### What does GHES support look like?

GHES support is planned but unlikely to happen within the next year. The plan
here is to provide a Cassandra based solution that will likely not be Datastax
Cassandra but a less resource intensive solution like ScyllaDB. There are a
couple of reasons, among them the fact there is no Azure SDK needed (as mentioned
in the API flavour section above). And thus integration in shipped environments
is easier as the language native DB clients can be used. Compatibility
here has been tested with Gremlin (graph API flavour that is also internally
backed by the Cassandra API) and no surprises have been found so far.
Generally CosmosDB Cassandra is a subset of the full Cassandra API. So if a
query works in CosmosDB it's going to be supported in vanilla Cassandra as
well most likely.

There is an official [support
matrix](https://learn.microsoft.com/en-us/azure/cosmos-db/cassandra/support)
for which Cassandra features are supported in CosmosDB's flavour.

### What does Proxima support look like?

Proxima support is looking good since it's already running in Azure. The
feature flag team is basing the new version of the service entirely on
CosmosDB in and outside of proxima.


[RUs]: https://learn.microsoft.com/en-us/azure/cosmos-db/request-units
[paved_path_backups]: https://github.com/github/CosmosDB/blob/main/docs/backup-restore.md
[paved_path_terraform]: https://github.com/github/CosmosDB/blob/main/docs/getting-started.md
[dd_cosmos]: https://app.datadoghq.com/screen/integration/30395/azure-cosmosdb?from_ts=1679649973256&to_ts=1679653573256&live=true
