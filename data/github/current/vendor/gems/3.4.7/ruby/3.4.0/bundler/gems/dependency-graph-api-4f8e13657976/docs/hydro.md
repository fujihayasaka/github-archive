## Dependency Graph & Hydro


### Kafka Overview
Dependency graph uses hydro to process messages for various background jobs and processes. Hydro uses kafka which is a distributed messaging system that provides fast, highly scalable and redundant messaging; to ensure continuous streaming and management of data. Dependency graph in particular uses the [ruby-kafka](https://github.com/zendesk/ruby-kafka) gem to make our kafka clients.

The basic architecture of kafka is organized around the terms:
- [Topic](https://kafka.apache.org/documentation/#intro_topics) : A category or feed name from which messages are published to or read from. Each topic is broken down into a group of ordered commit logs called partitions, and data is retained in a topic for a specified period of time.

- [Producer](https://kafka.apache.org/documentation/#intro_producers) : Pushes messages to a kafka topic.

- [Consumer](https://kafka.apache.org/documentation/#intro_consumers) : Pulls messages down from a kafka topic to be consumed.

- [Broker](https://kafka.apache.org/intro#intro_distribution) : A kafka server that hosts all the topics. The broker which is essentially a node in a cluster, acts as a contoller for the cluster; regulating how messages are received from producer and how they are given to the consumer.

More details can be found in [kafka docs](https://kafka.apache.org/), and a quick [overview](https://sookocheff.com/post/kafka/kafka-in-a-nutshell/) of kafka here.

#### Local Development

We use [kafka-lite](https://github.com/github/kafka-lite) to simulate Kafka in our development environment. You can see the configuration (and list of topics to seed in development)
in our [docker-compose.yml file](https://github.com/github/dependency-graph-api/blob/kafka-lite/docker-compose.yml#L39-L58).

**Tip!** If you add a new topic, make sure to add it to the development configuration above!

### Dependency Graph Hydro Configuration

- Topic: Topics for dependency graph are created in the [hydro-schemas](https://github.com/github/hydro-schemas) repository and are managed by GitHub's hydro and data-pipelines team. The hydro schemas repository is also responsible for generating protobufs for the various topics that help consumers/producers process messages in a structured manner. The topics dependency graph reads from can be found in the repository's kafka config.

- Producer: For most of our topics, producers are created in [dotcom](https://github.com/github/github/blob/master/config/instrumentation/hydro.rb) by subscribing to topics created in hydro, and publishing to them.

- Consumer: Our consumers are defined in dependency graph api and act on the messages. An example of how we consume messages can be found [here](https://github.com/github/dependency-graph-api/blob/master/etl/kafka_sink/repository_manifest_file_change_sink.rb)

- Brokers: We set our connection to desired brokers in dependency graph in our kafka config file.

Our kafka configuration is defined in our [kafka.yml](https://github.com/github/dependency-graph-api/blob/master/config/kafka.yml)


### Daemon Workers Using Hydro
List of workers we have that use hydro can be found [here](https://github.com/github/dependency-graph-api/blob/master/docs/workers.md#daemon-workers)


### Observability
Our Hydro processes are monitored with datadog. All hydro services come with [burrow](https://github.com/linkedin/Burrow) which monitors the Hydro Kafka cluster, and will determine if there are any issues - such as consumers not reading messages. Visibility into the various processes running is very useful in validating that our workers are running successfully.

A myriad of tools are used to observe the status of our hydro workers:

#### Chatops
##### Inlines a semi-formatted table of the most recent 8 events for a hydro topic.
```
.hydro tail <topic>
```
##### For example:
```
.hydro tail cp1-iad.ingest.github.v1.RepositoryDeleted
```

##### Inlines a graph from a datadog dashboard.
```
.dash me -1h [DASHBOARD]/[GRAPH] --event_type [EVENT]
```
##### For example:
```
.dash me -1h dependency-graph.api/API requests
```
`--event_type` parameter is optional

List of dependency graph dashboards can be found [here](https://github.com/github/dependency-graph-api#performance-dashboard)

#### Observing process and flow
These tools help us verify that processed that leverage hydro are running and are healthy.

- [Simple Ingest Dashboard](https://app.datadoghq.com/dash/915257/simple-ingest-dash?tile_size=m) which you can use to see kafka messages being consumed and if there is any consumer lag.

- [Main hydro dashboard](https://app.datadoghq.com/dash/170044/hydrokafka?tile_size=m) for all of GitHub.

- [Consumer dashboard](https://app.datadoghq.com/dash/897912/hydrotopic?tile_size=m) where one has to enter the desired topic and consumer group and various metrics about consumer would be shown.

- [Tributary](https://tributary.githubapp.com/) shows you message production/consumption rate, and sample payload of a kafka message for a specific topic.

#### Observing messages
These tools give us insight into the actual messages that are being sent in our hydro services. The tools below will only work on topics that have some degree of message retention.

- [Kafkacat](https://github.com/edenhill/kafkacat) which is a CLI tool to access data on a particular kafka topic. Kafkacat requires GitHub VPN access, and to have the package installed locally on one's computer.
```
apt-get install kafkacat # On Debian OR
brew install kafkacat # On Mac OS X with homebrew installed
```

#### Useful Kafkacat commands

Useful flags:
```
-p: partition number   -e: exit
-t: topic,             -o: offset
-b: broker             -c: cutoff
-C: Consumer           -P: Producer
```

##### Read messages from topic and print to stdout
```
$ kafkacat -b <mybroker> -t <mytopic>
```
##### For Example
```
$ kafkacat -C -b hydro-kafka-potomac-boot-1.service.cp1-iad.github.net -t cp1-iad.ingest.github.v1.RepositoryVisibilityChanged
```

##### Read the last desired n number of messages from topic, then exit
```
$ kafkacat -C -b <mybroker> -t <mytopic> -p 0 -o -<number> -e
```
##### For Example
```
$ kafkacat -C -b hydro-kafka-potomac-boot-1.service.cp1-iad.github.net -t cp1-iad.ingest.github.v1.RepositoryVisibilityChanged -p 0 -o -10 -e
# reads last 10 messages then exits
```

##### Read message at a desired offset
```
kafkacat -b <mybroker> -t <mytopic> -p <partition-number> -o <offset-number> -c 1
```

##### For Example
```
kafkacat -b hydro-kafka-potomac-boot-1.service.cp1-iad.github.net -t cp1-iad.ingest.github.dependencygraph.v0.RepositoryManifestFileChange -p 3 -o 1000 -c 1
# reads message at offset 1000
```

More examples of kafkacat queries can be found [here](https://github.com/edenhill/kafkacat#examples)

- [Presto Console](https://github.com/github/data-engineering/blob/master/docs/Presto.md)  is a CLI that can be used to access hydro topic data. Octoquery below is a web app  version that leverages presto;  a distributed SQL query engine. Presto can be accessed through the bastion host if one has right entitlements.
```
$ ssh bastion.githubapp.com # Log into bastion using your Duo 2FA

$ ssh analytics-console.github.net # Log onto the analytics console host

gh-presto console # Start the interactive Presto prompt
```

- [Octoquery](https://octoquery-production.service.cp1-iad.github.net/) which is a centralized Presto query UI for GitHub that provides permalinks for sharing, caches results for later use, and allows assisted table schema navigation. Octoquery is essentially a web interface made to query Presto. To use octoquery, one must be logged in via our [vpn](https://githubber.com/article/technology/production-vpn-access).

Presto uses SQL to query its datastore. Common queries to run on our hydro message data while debugging would involve a selection of some sort on a desired topic with given constraints in form shown below:

```
# General Structure
select *
from
 hive_hydro.<topic-schema-name>
where ....
order by ...
```

Example presto queries than can be run in Presto Console/octoquery:

##### Selects 10 most recent visibility changed events from repository_visibility_changed topic
```
select *
from
 hive_hydro.hydro.github_v1_repository_visibility_changed
order by timestamp desc limit 10;
```

##### Selects the 20 most recent repository deleted events from repository_deleted topic in given date range
```
select
*
from
 hive_hydro.hydro.github_v1_repository_deleted
where
 day > '2018-12-18' and day < '2018-12-20'
order by timestamp desc limit 20;
```

For more information on Hydro, check out the [Hydro repository](https://github.com/github/hydro) or [Data Pipelines team repository](https://github.com/github/data-pipelines).
