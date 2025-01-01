// DO NOT EDIT MANUALLY!!! Code generated from github/github-semantic-conventions/go/templates/keys.j2

// Deprecated: services should use the semantic conventions directly
// As of https://github.com/github/observability/pull/3479 this code will no
// longer be kept up to date with the latest conventions
package keys

// Span attributes used by AWS Lambda (in addition to general `faas` attributes).
type awsLambda struct {
	// InvokedArn is the string value of the aws.lambda.invoked_arn key
	//
	// The full invoked ARN as provided on the `Context` passed to the function (`Lambda-Runtime-
	// Invoked-Function-Arn` header on the `/runtime/invocation/next` applicable).
	//
	// Type: string
	//
	// Examples:
	//   'arn:aws:lambda:us-east-1:123456:function:myfunction:myalias'
	//
	// Note:
	// This may be different from `faas.id` if an alias is involved.
	InvokedArn string
}

// Span attributes used by AWS Lambda (in addition to general `faas` attributes).
var AwsLambda = awsLambda{
	InvokedArn: "aws.lambda.invoked_arn",
}

// This document specifies common metadata specific to Azure resources provisioned on behalf of
// users. For  Azure resources provisioned as GitHub infrastructure, use the `github-infra`
// conventions..
type ghAzure struct {
	// Location is the string value of the gh.azure.location key
	//
	// An Azure location.
	//
	// Type: string
	//
	// Examples:
	//   'West US', 'East US'
	Location string
}

// This document specifies common metadata specific to Azure resources provisioned on behalf of
// users. For  Azure resources provisioned as GitHub infrastructure, use the `github-infra`
// conventions..
var GhAzure = ghAzure{
	Location: "gh.azure.location",
}

// This document defines attributes for CloudEvents. CloudEvents is a specification on how to define
// event data in a standard way. These attributes can be attached to spans when performing
// operations with CloudEvents, regardless of the protocol being used.
type cloudevents struct {
	// EventId is the string value of the cloudevents.event_id key
	//
	// The [event_id](https://github.com/cloudevents/spec/blob/v1.0.2/cloudevents/spec.md#id) uniquely
	// identifies the event.
	//
	// Type: string
	//
	// Requirement Level: Required
	//
	// Examples:
	//   '123e4567-e89b-12d3-a456-426614174000', '0001'
	EventId string
	// EventSource is the string value of the cloudevents.event_source key
	//
	// The [source](https://github.com/cloudevents/spec/blob/v1.0.2/cloudevents/spec.md#source-1)
	// identifies the context in which an event happened.
	//
	// Type: string
	//
	// Requirement Level: Required
	//
	// Examples:
	//   'https://github.com/cloudevents', '/cloudevents/spec/pull/123', 'my-service'
	EventSource string
	// EventSpecVersion is the string value of the cloudevents.event_spec_version key
	//
	// The [version of the CloudEvents
	// specification](https://github.com/cloudevents/spec/blob/v1.0.2/cloudevents/spec.md#specversion)
	// which the event uses.
	//
	// Type: string
	//
	// Examples:
	//   '1.0'
	EventSpecVersion string
	// EventType is the string value of the cloudevents.event_type key
	//
	// The [event_type](https://github.com/cloudevents/spec/blob/v1.0.2/cloudevents/spec.md#type)
	// contains a value describing the type of event related to the originating occurrence.
	//
	// Type: string
	//
	// Examples:
	//   'com.github.pull_request.opened', 'com.example.object.deleted.v2'
	EventType string
	// EventSubject is the string value of the cloudevents.event_subject key
	//
	// The [subject](https://github.com/cloudevents/spec/blob/v1.0.2/cloudevents/spec.md#subject) of the
	// event in the context of the event producer (identified by source).
	//
	// Type: string
	//
	// Examples:
	//   'mynewfile.jpg'
	EventSubject string
}

// This document defines attributes for CloudEvents. CloudEvents is a specification on how to define
// event data in a standard way. These attributes can be attached to spans when performing
// operations with CloudEvents, regardless of the protocol being used.
var Cloudevents = cloudevents{
	EventId:          "cloudevents.event_id",
	EventSource:      "cloudevents.event_source",
	EventSpecVersion: "cloudevents.event_spec_version",
	EventType:        "cloudevents.event_type",
	EventSubject:     "cloudevents.event_subject",
}

// This document defines semantic conventions for the OpenTracing Shim
type opentracing struct {
	// RefType is the string value of the opentracing.ref_type key
	//
	// Parent-child Reference type
	//
	// Type: Enum
	//
	// Note:
	// The causal relationship between a child Span and a parent Span.
	RefType string
}

// This document defines semantic conventions for the OpenTracing Shim
var Opentracing = opentracing{
	RefType: "opentracing.ref_type",
}

// This document defines the attributes used to perform database client calls.
type db struct {
	// System is the string value of the db.system key
	//
	// An identifier for the database management system (DBMS) product being used. See below for a list
	// of well-known identifiers.
	//
	// Type: Enum
	//
	// Requirement Level: Required
	System string
	// ConnectionString is the string value of the db.connection_string key
	//
	// The connection string used to connect to the database. It is recommended to remove embedded
	// credentials.
	//
	// Type: string
	//
	// Examples:
	//   'Server=(localdb)\\v11.0;Integrated Security=true;'
	ConnectionString string
	// User is the string value of the db.user key
	//
	// Username for accessing the database.
	//
	// Type: string
	//
	// Examples:
	//   'readonly_user', 'reporting_user'
	User string
	// JcDriverClassname is the string value of the db.jdbc.driver_classname key
	//
	// The fully-qualified class name of the [Java Database Connectivity
	// (JDBC)](https://docs.oracle.com/javase/8/docs/technotes/guides/jdbc/) driver used to connect.
	//
	// Type: string
	//
	// Examples:
	//   'org.postgresql.Driver', 'com.microsoft.sqlserver.jdbc.SQLServerDriver'
	JcDriverClassname string
	// Name is the string value of the db.name key
	//
	// This attribute is used to report the name of the database being accessed. For commands that
	// switch the database, this should be set to the target database (even if the command fails).
	//
	// Type: string
	//
	// Requirement Level: Conditionally Required - If applicable.
	//
	// Examples:
	//   'customers', 'main'
	//
	// Note:
	// In some SQL databases, the database name to be used is called "schema name". In case there are
	// multiple layers that could be considered for database name (e.g. Oracle instance name and
	// schema name), the database name to be used is the more specific layer (e.g. Oracle schema
	// name).
	Name string
	// Statement is the string value of the db.statement key
	//
	// The database statement being executed.
	//
	// Type: string
	//
	// Requirement Level: Conditionally Required - If applicable and not explicitly disabled via instrumentation configuration.
	//
	// Examples:
	//   'SELECT * FROM wuser_table', 'SET mykey "WuValue"'
	//
	// Note:
	// The value may be sanitized to exclude sensitive information.
	Statement string
	// Operation is the string value of the db.operation key
	//
	// The name of the operation being executed, e.g. the [MongoDB command
	// name](https://docs.mongodb.com/manual/reference/command/#database-operations) such as
	// `findAndModify`, or the SQL keyword.
	//
	// Type: string
	//
	// Requirement Level: Conditionally Required - If `db.statement` is not applicable.
	//
	// Examples:
	//   'findAndModify', 'HMSET', 'SELECT'
	//
	// Note:
	// When setting this to an SQL keyword, it is not recommended to attempt any client-side parsing
	// of `db.statement` just to get this property, but it should be set if the operation name is
	// provided by the library being instrumented. If the SQL statement has an ambiguous operation,
	// or performs more than one operation, this value may be omitted.
	Operation string
}

// This document defines the attributes used to perform database client calls.
var Db = db{
	System:            "db.system",
	ConnectionString:  "db.connection_string",
	User:              "db.user",
	JcDriverClassname: "db.jdbc.driver_classname",
	Name:              "db.name",
	Statement:         "db.statement",
	Operation:         "db.operation",
}

// Connection-level attributes for Microsoft SQL Server
type dbMssql struct {
	// InstanceName is the string value of the db.mssql.instance_name key
	//
	// The Microsoft SQL Server [instance name](https://docs.microsoft.com/en-
	// us/sql/connect/jdbc/building-the-connection-url?view=sql-server-ver15) connecting to. This name
	// is used to determine the port of a named instance.
	//
	// Type: string
	//
	// Examples:
	//   'MSSQLSERVER'
	//
	// Note:
	// If setting a `db.mssql.instance_name`, `net.peer.port` is no longer required (but still
	// recommended if non-standard).
	InstanceName string
}

// Connection-level attributes for Microsoft SQL Server
var DbMssql = dbMssql{
	InstanceName: "db.mssql.instance_name",
}

// Call-level attributes for Cassandra
type dbCassandra struct {
	// PageSize is the string value of the db.cassandra.page_size key
	//
	// The fetch size used for paging, i.e. how many rows will be returned at once.
	//
	// Type: int
	//
	// Examples:
	//   5000
	PageSize string
	// ConsistencyLevel is the string value of the db.cassandra.consistency_level key
	//
	// The consistency level of the query. Based on consistency values from
	// [CQL](https://docs.datastax.com/en/cassandra-oss/3.0/cassandra/dml/dmlConfigConsistency.html).
	//
	// Type: Enum
	ConsistencyLevel string
	// Table is the string value of the db.cassandra.table key
	//
	// The name of the primary table that the operation is acting upon, including the keyspace name (if
	// applicable).
	//
	// Type: string
	//
	// Requirement Level: Recommended
	//
	// Examples:
	//   'mytable'
	//
	// Note:
	// This mirrors the db.sql.table attribute but references cassandra rather than sql. It is not
	// recommended to attempt any client-side parsing of `db.statement` just to get this property,
	// but it should be set if it is provided by the library being instrumented. If the operation is
	// acting upon an anonymous table, or more than one table, this value MUST NOT be set.
	Table string
	// Idempotence is the string value of the db.cassandra.idempotence key
	//
	// Whether or not the query is idempotent.
	//
	// Type: boolean
	Idempotence string
	// SpeculativeExecutionCount is the string value of the db.cassandra.speculative_execution_count key
	//
	// The number of times a query was speculatively executed. Not set or `0` if the query was not
	// executed speculatively.
	//
	// Type: int
	//
	// Examples:
	//   0, 2
	SpeculativeExecutionCount string
	// CoordinatorId is the string value of the db.cassandra.coordinator.id key
	//
	// The ID of the coordinating node for a query.
	//
	// Type: string
	//
	// Examples:
	//   'be13faa2-8574-4d71-926d-27f16cf8a7af'
	CoordinatorId string
	// CoordinatorDc is the string value of the db.cassandra.coordinator.dc key
	//
	// The data center of the coordinating node for a query.
	//
	// Type: string
	//
	// Examples:
	//   'us-west-2'
	CoordinatorDc string
}

// Call-level attributes for Cassandra
var DbCassandra = dbCassandra{
	PageSize:                  "db.cassandra.page_size",
	ConsistencyLevel:          "db.cassandra.consistency_level",
	Table:                     "db.cassandra.table",
	Idempotence:               "db.cassandra.idempotence",
	SpeculativeExecutionCount: "db.cassandra.speculative_execution_count",
	CoordinatorId:             "db.cassandra.coordinator.id",
	CoordinatorDc:             "db.cassandra.coordinator.dc",
}

// Call-level attributes for Redis
type dbRedis struct {
	// DatabaseIndex is the string value of the db.redis.database_index key
	//
	// The index of the database being accessed as used in the [`SELECT`
	// command](https://redis.io/commands/select), provided as an integer. To be used instead of the
	// generic `db.name` attribute.
	//
	// Type: int
	//
	// Requirement Level: Conditionally Required - If other than the default database (`0`).
	//
	// Examples:
	//   0, 1, 15
	DatabaseIndex string
}

// Call-level attributes for Redis
var DbRedis = dbRedis{
	DatabaseIndex: "db.redis.database_index",
}

// Call-level attributes for MongoDB
type dbMongodb struct {
	// Collection is the string value of the db.mongodb.collection key
	//
	// The collection being accessed within the database stated in `db.name`.
	//
	// Type: string
	//
	// Requirement Level: Required
	//
	// Examples:
	//   'customers', 'products'
	Collection string
}

// Call-level attributes for MongoDB
var DbMongodb = dbMongodb{
	Collection: "db.mongodb.collection",
}

// Call-level attributes for SQL databases
type dbSql struct {
	// Table is the string value of the db.sql.table key
	//
	// The name of the primary table that the operation is acting upon, including the database name (if
	// applicable).
	//
	// Type: string
	//
	// Requirement Level: Recommended
	//
	// Examples:
	//   'public.users', 'customers'
	//
	// Note:
	// It is not recommended to attempt any client-side parsing of `db.statement` just to get this
	// property, but it should be set if it is provided by the library being instrumented. If the
	// operation is acting upon an anonymous table, or more than one table, this value MUST NOT be
	// set.
	Table string
}

// Call-level attributes for SQL databases
var DbSql = dbSql{
	Table: "db.sql.table",
}

// Semantic convention group for specific technologies
type dbTech struct {
}

// Semantic convention group for specific technologies
var DbTech = dbTech{}

// This document defines the attributes used to report a single exception associated with a span.
type exception struct {
	// Type is the string value of the exception.type key
	//
	// The type of the exception (its fully-qualified class name, if applicable). The dynamic type of
	// the exception should be preferred over the static type in languages that support it.
	//
	// Type: string
	//
	// Examples:
	//   'java.net.ConnectException', 'OSError'
	Type string
	// Message is the string value of the exception.message key
	//
	// The exception message.
	//
	// Type: string
	//
	// Examples:
	//   'Division by zero', "Can't convert 'int' object to str implicitly"
	Message string
	// Stacktrace is the string value of the exception.stacktrace key
	//
	// A stacktrace as a string in the natural representation for the language runtime. The
	// representation is to be determined and documented by each language SIG.
	//
	// Type: string
	//
	// Examples:
	//   'Exception in thread "main" java.lang.RuntimeException: Test exception\\n at '
	//  'com.example.GenerateTrace.methodB(GenerateTrace.java:13)\\n at '
	//  'com.example.GenerateTrace.methodA(GenerateTrace.java:9)\\n at '
	//  'com.example.GenerateTrace.main(GenerateTrace.java:5)'
	Stacktrace string
	// Escaped is the string value of the exception.escaped key
	//
	// SHOULD be set to true if the exception event is recorded at a point where it is known that the
	// exception is escaping the scope of the span.
	//
	// Type: boolean
	//
	// Note:
	// An exception is considered to have escaped (or left) the scope of a span, if that span is
	// ended while the exception is still logically "in flight". This may be actually "in flight" in
	// some languages (e.g. if the exception is passed to a Context manager's `__exit__` method in
	// Python) but will usually be caught at the point of recording the exception in most languages.
	//
	// It is usually not possible to determine at the point where an exception is thrown whether it
	// will escape the scope of a span. However, it is trivial to know that an exception will escape,
	// if one checks for an active exception just before ending the span, as done in the example
	// above.
	//
	// It follows that an exception may still escape the scope of the span even if the
	// `exception.escaped` attribute was not set or set to false, since the event might have been
	// recorded at a time where it was not clear whether the exception will escape.
	Escaped string
}

// This document defines the attributes used to report a single exception associated with a span.
var Exception = exception{
	Type:       "exception.type",
	Message:    "exception.message",
	Stacktrace: "exception.stacktrace",
	Escaped:    "exception.escaped",
}

// This semantic convention describes an instance of a function that runs without provisioning or
// managing of servers (also known as serverless functions or Function as a Service (FaaS)) with
// spans.
type faasSpan struct {
	// Trigger is the string value of the faas.trigger key
	//
	// Type of the trigger which caused this function execution.
	//
	// Type: Enum
	//
	// Note:
	// For the server/consumer span on the incoming side, `faas.trigger` MUST be set.
	//
	// Clients invoking FaaS instances usually cannot set `faas.trigger`, since they would typically
	// need to look in the payload to determine the event type. If clients set it, it should be the
	// same as the trigger that corresponding incoming would have (i.e., this has nothing to do with
	// the underlying transport used to make the API call to invoke the lambda, which is often HTTP).
	Trigger string
	// Execution is the string value of the faas.execution key
	//
	// The execution ID of the current function execution.
	//
	// Type: string
	//
	// Examples:
	//   'af9d5aa4-a685-4c5f-a22b-444f80b3cc28'
	Execution string
}

// This semantic convention describes an instance of a function that runs without provisioning or
// managing of servers (also known as serverless functions or Function as a Service (FaaS)) with
// spans.
var FaasSpan = faasSpan{
	Trigger:   "faas.trigger",
	Execution: "faas.execution",
}

// Semantic Convention for FaaS triggered as a response to some data source operation such as a
// database or filesystem read/write.
type faasSpanDatasource struct {
	// Collection is the string value of the faas.document.collection key
	//
	// The name of the source on which the triggering operation was performed. For example, in Cloud
	// Storage or S3 corresponds to the bucket name, and in Cosmos DB to the database name.
	//
	// Type: string
	//
	// Requirement Level: Required
	//
	// Examples:
	//   'myBucketName', 'myDbName'
	Collection string
	// Operation is the string value of the faas.document.operation key
	//
	// Describes the type of the operation that was performed on the data.
	//
	// Type: Enum
	//
	// Requirement Level: Required
	Operation string
	// Time is the string value of the faas.document.time key
	//
	// A string containing the time when the data was accessed in the [ISO
	// 8601](https://www.iso.org/iso-8601-date-and-time-format.html) format expressed in
	// [UTC](https://www.w3.org/TR/NOTE-datetime).
	//
	// Type: string
	//
	// Examples:
	//   '2020-01-23T13:47:06Z'
	Time string
	// Name is the string value of the faas.document.name key
	//
	// The document name/table subjected to the operation. For example, in Cloud Storage or S3 is the
	// name of the file, and in Cosmos DB the table name.
	//
	// Type: string
	//
	// Examples:
	//   'myFile.txt', 'myTableName'
	Name string
}

// Semantic Convention for FaaS triggered as a response to some data source operation such as a
// database or filesystem read/write.
var FaasSpanDatasource = faasSpanDatasource{
	Collection: "faas.document.collection",
	Operation:  "faas.document.operation",
	Time:       "faas.document.time",
	Name:       "faas.document.name",
}

// Semantic Convention for FaaS triggered as a response to some data source operation such as a
// database or filesystem read/write.
type faasSpanHttp struct {
}

// Semantic Convention for FaaS triggered as a response to some data source operation such as a
// database or filesystem read/write.
var FaasSpanHttp = faasSpanHttp{}

// Semantic Convention for FaaS set to be executed when messages are sent to a messaging system.
type faasSpanPubsub struct {
}

// Semantic Convention for FaaS set to be executed when messages are sent to a messaging system.
var FaasSpanPubsub = faasSpanPubsub{}

// Semantic Convention for FaaS scheduled to be executed regularly.
type faasSpanTimer struct {
	// Time is the string value of the faas.time key
	//
	// A string containing the function invocation time in the [ISO
	// 8601](https://www.iso.org/iso-8601-date-and-time-format.html) format expressed in
	// [UTC](https://www.w3.org/TR/NOTE-datetime).
	//
	// Type: string
	//
	// Examples:
	//   '2020-01-23T13:47:06Z'
	Time string
	// Cron is the string value of the faas.cron key
	//
	// A string containing the schedule period as [Cron
	// Expression](https://docs.oracle.com/cd/E12058_01/doc/doc.1014/e12030/cron_expressions.htm).
	//
	// Type: string
	//
	// Examples:
	//   '0/5 * * * ? *'
	Cron string
}

// Semantic Convention for FaaS scheduled to be executed regularly.
var FaasSpanTimer = faasSpanTimer{
	Time: "faas.time",
	Cron: "faas.cron",
}

// Contains additional attributes for incoming FaaS spans.
type faasSpanIn struct {
	// Coldstart is the string value of the faas.coldstart key
	//
	// A boolean that is true if the serverless function is executed for the first time (aka cold-
	// start).
	//
	// Type: boolean
	Coldstart string
}

// Contains additional attributes for incoming FaaS spans.
var FaasSpanIn = faasSpanIn{
	Coldstart: "faas.coldstart",
}

// Contains additional attributes for outgoing FaaS spans.
type faasSpanOut struct {
	// InvokedName is the string value of the faas.invoked_name key
	//
	// The name of the invoked function.
	//
	// Type: string
	//
	// Requirement Level: Required
	//
	// Examples:
	//   'my-function'
	//
	// Note:
	// SHOULD be equal to the `faas.name` resource attribute of the invoked function.
	InvokedName string
	// InvokedProvider is the string value of the faas.invoked_provider key
	//
	// The cloud provider of the invoked function.
	//
	// Type: Enum
	//
	// Requirement Level: Required
	//
	// Note:
	// SHOULD be equal to the `cloud.provider` resource attribute of the invoked function.
	InvokedProvider string
	// InvokedRegion is the string value of the faas.invoked_region key
	//
	// The cloud region of the invoked function.
	//
	// Type: string
	//
	// Requirement Level: Conditionally Required - For some cloud providers, like AWS or GCP, the region in which a function is hosted is essential to uniquely identify the function and also part of its endpoint. Since it's part of the endpoint being called, the region is always known to clients. In these cases, `faas.invoked_region` MUST be set accordingly. If the region is unknown to the client or not required for identifying the invoked function, setting `faas.invoked_region` is optional.
	//
	// Examples:
	//   'eu-central-1'
	//
	// Note:
	// SHOULD be equal to the `cloud.region` resource attribute of the invoked function.
	InvokedRegion string
}

// Contains additional attributes for outgoing FaaS spans.
var FaasSpanOut = faasSpanOut{
	InvokedName:     "faas.invoked_name",
	InvokedProvider: "faas.invoked_provider",
	InvokedRegion:   "faas.invoked_region",
}

// These attributes may be used for any network related operation.
type network struct {
	// Transport is the string value of the net.transport key
	//
	// Transport protocol used. See note below.
	//
	// Type: Enum
	Transport string
	// AppProtocolName is the string value of the net.app.protocol.name key
	//
	// Application layer protocol used. The value SHOULD be normalized to lowercase.
	//
	// Type: string
	//
	// Examples:
	//   'amqp', 'http', 'mqtt'
	AppProtocolName string
	// AppProtocolVersion is the string value of the net.app.protocol.version key
	//
	// Version of the application layer protocol used. See note below.
	//
	// Type: string
	//
	// Examples:
	//   '3.1.1'
	//
	// Note:
	// `net.app.protocol.version` refers to the version of the protocol used and might be different
	// from the protocol client's version. If the HTTP client used has a version of `0.27.2`, but
	// sends HTTP version `1.1`, this attribute should be set to `1.1`.
	AppProtocolVersion string
	// SockPeerName is the string value of the net.sock.peer.name key
	//
	// Remote socket peer name.
	//
	// Type: string
	//
	// Requirement Level: Recommended
	//
	// Examples:
	//   'proxy.example.com'
	SockPeerName string
	// SockPeerAddr is the string value of the net.sock.peer.addr key
	//
	// Remote socket peer address: IPv4 or IPv6 for internet protocols, path for local communication,
	// [etc](https://man7.org/linux/man-pages/man7/address_families.7.html).
	//
	// Type: string
	//
	// Examples:
	//   '127.0.0.1', '/tmp/mysql.sock'
	SockPeerAddr string
	// SockPeerPort is the string value of the net.sock.peer.port key
	//
	// Remote socket peer port.
	//
	// Type: int
	//
	// Requirement Level: Recommended
	//
	// Examples:
	//   16456
	SockPeerPort string
	// SockFamily is the string value of the net.sock.family key
	//
	// Protocol [address family](https://man7.org/linux/man-pages/man7/address_families.7.html) which is
	// used for communication.
	//
	// Type: Enum
	//
	// Requirement Level: Conditionally Required - If different than `inet` and if any of `net.sock.peer.addr` or `net.sock.host.addr` are set. Consumers of telemetry SHOULD accept both IPv4 and IPv6 formats for the address in `net.sock.peer.addr` if `net.sock.family` is not set. This is to support instrumentations that follow previous versions of this document.
	//
	// Examples:
	//   'inet6', 'bluetooth'
	SockFamily string
	// PeerName is the string value of the net.peer.name key
	//
	// Logical remote hostname, see note below.
	//
	// Type: string
	//
	// Examples:
	//   'example.com'
	//
	// Note:
	// `net.peer.name` SHOULD NOT be set if capturing it would require an extra DNS lookup.
	PeerName string
	// PeerPort is the string value of the net.peer.port key
	//
	// Logical remote port number
	//
	// Type: int
	//
	// Examples:
	//   80, 8080, 443
	PeerPort string
	// HostName is the string value of the net.host.name key
	//
	// Logical local hostname or similar, see note below.
	//
	// Type: string
	//
	// Examples:
	//   'localhost'
	HostName string
	// HostPort is the string value of the net.host.port key
	//
	// Logical local port number, preferably the one that the peer used to connect
	//
	// Type: int
	//
	// Examples:
	//   8080
	HostPort string
	// SockHostAddr is the string value of the net.sock.host.addr key
	//
	// Local socket address. Useful in case of a multi-IP host.
	//
	// Type: string
	//
	// Examples:
	//   '192.168.0.1'
	SockHostAddr string
	// SockHostPort is the string value of the net.sock.host.port key
	//
	// Local socket port number.
	//
	// Type: int
	//
	// Requirement Level: Recommended
	//
	// Examples:
	//   35555
	SockHostPort string
	// HostConnectionType is the string value of the net.host.connection.type key
	//
	// The internet connection type currently being used by the host.
	//
	// Type: Enum
	//
	// Examples:
	//   'wifi'
	HostConnectionType string
	// HostConnectionSubtype is the string value of the net.host.connection.subtype key
	//
	// This describes more details regarding the connection.type. It may be the type of cell technology
	// connection, but it could be used for describing details about a wifi connection.
	//
	// Type: Enum
	//
	// Examples:
	//   'LTE'
	HostConnectionSubtype string
	// HostCarrierName is the string value of the net.host.carrier.name key
	//
	// The name of the mobile carrier.
	//
	// Type: string
	//
	// Examples:
	//   'sprint'
	HostCarrierName string
	// HostCarrierMcc is the string value of the net.host.carrier.mcc key
	//
	// The mobile carrier country code.
	//
	// Type: string
	//
	// Examples:
	//   '310'
	HostCarrierMcc string
	// HostCarrierMnc is the string value of the net.host.carrier.mnc key
	//
	// The mobile carrier network code.
	//
	// Type: string
	//
	// Examples:
	//   '001'
	HostCarrierMnc string
	// HostCarrierIcc is the string value of the net.host.carrier.icc key
	//
	// The ISO 3166-1 alpha-2 2-character country code associated with the mobile carrier network.
	//
	// Type: string
	//
	// Examples:
	//   'DE'
	HostCarrierIcc string
}

// These attributes may be used for any network related operation.
var Network = network{
	Transport:             "net.transport",
	AppProtocolName:       "net.app.protocol.name",
	AppProtocolVersion:    "net.app.protocol.version",
	SockPeerName:          "net.sock.peer.name",
	SockPeerAddr:          "net.sock.peer.addr",
	SockPeerPort:          "net.sock.peer.port",
	SockFamily:            "net.sock.family",
	PeerName:              "net.peer.name",
	PeerPort:              "net.peer.port",
	HostName:              "net.host.name",
	HostPort:              "net.host.port",
	SockHostAddr:          "net.sock.host.addr",
	SockHostPort:          "net.sock.host.port",
	HostConnectionType:    "net.host.connection.type",
	HostConnectionSubtype: "net.host.connection.subtype",
	HostCarrierName:       "net.host.carrier.name",
	HostCarrierMcc:        "net.host.carrier.mcc",
	HostCarrierMnc:        "net.host.carrier.mnc",
	HostCarrierIcc:        "net.host.carrier.icc",
}

// Operations that access some remote service.
type peer struct {
	// Service is the string value of the peer.service key
	//
	// The [`service.name`](../../resource/semantic_conventions/README.md#service) of the remote
	// service. SHOULD be equal to the actual `service.name` resource attribute of the remote service if
	// any.
	//
	// Type: string
	//
	// Examples:
	//   'AuthTokenCache'
	Service string
}

// Operations that access some remote service.
var Peer = peer{
	Service: "peer.service",
}

// These attributes may be used for any operation with an authenticated and/or authorized enduser.
type identity struct {
	// Id is the string value of the enduser.id key
	//
	// Username or client_id extracted from the access token or
	// [Authorization](https://tools.ietf.org/html/rfc7235#section-4.2) header in the inbound request
	// from outside the system.
	//
	// Type: string
	//
	// Examples:
	//   'username'
	Id string
	// Role is the string value of the enduser.role key
	//
	// Actual/assumed role the client is making the request under extracted from token or application
	// security context.
	//
	// Type: string
	//
	// Examples:
	//   'admin'
	Role string
	// Scope is the string value of the enduser.scope key
	//
	// Scopes or granted authorities the client currently possesses extracted from token or application
	// security context. The value would come from the scope associated with an [OAuth 2.0 Access
	// Token](https://tools.ietf.org/html/rfc6749#section-3.3) or an attribute value in a [SAML 2.0
	// Assertion](http://docs.oasis-open.org/security/saml/Post2.0/sstc-saml-tech-overview-2.0.html).
	//
	// Type: string
	//
	// Examples:
	//   'read:message, write:files'
	Scope string
}

// These attributes may be used for any operation with an authenticated and/or authorized enduser.
var Identity = identity{
	Id:    "enduser.id",
	Role:  "enduser.role",
	Scope: "enduser.scope",
}

// These attributes may be used for any operation to store information about a thread that started a
// span.
type thread struct {
	// Id is the string value of the thread.id key
	//
	// Current "managed" thread ID (as opposed to OS thread ID).
	//
	// Type: int
	//
	// Examples:
	//   42
	Id string
	// Name is the string value of the thread.name key
	//
	// Current thread name.
	//
	// Type: string
	//
	// Examples:
	//   'main'
	Name string
}

// These attributes may be used for any operation to store information about a thread that started a
// span.
var Thread = thread{
	Id:   "thread.id",
	Name: "thread.name",
}

// These attributes allow to report this unit of code and therefore to provide more context about
// the span.
type code struct {
	// Function is the string value of the code.function key
	//
	// The method or function name, or equivalent (usually rightmost part of the code unit's name).
	//
	// Type: string
	//
	// Examples:
	//   'serveRequest'
	Function string
	// Namespace is the string value of the code.namespace key
	//
	// The "namespace" within which `code.function` is defined. Usually the qualified class or module
	// name, such that `code.namespace` + some separator + `code.function` form a unique identifier for
	// the code unit.
	//
	// Type: string
	//
	// Examples:
	//   'com.example.MyHttpService'
	Namespace string
	// Filepath is the string value of the code.filepath key
	//
	// The source code file name that identifies the code unit as uniquely as possible (preferably an
	// absolute file path).
	//
	// Type: string
	//
	// Examples:
	//   '/usr/local/MyApplication/content_root/app/index.php'
	Filepath string
	// Lineno is the string value of the code.lineno key
	//
	// The line number in `code.filepath` best representing the operation. It SHOULD point within the
	// code unit named in `code.function`.
	//
	// Type: int
	//
	// Examples:
	//   42
	Lineno string
}

// These attributes allow to report this unit of code and therefore to provide more context about
// the span.
var Code = code{
	Function:  "code.function",
	Namespace: "code.namespace",
	Filepath:  "code.filepath",
	Lineno:    "code.lineno",
}

// This document specifies common metadata specific to Git resources in user repositories.
type ghGit struct {
	// Ref is the string value of the gh.git.ref key
	//
	// A Git ref.
	//
	// Type: string
	//
	// Examples:
	//   'refs/heads/main', 'refs/tags/v1.0'
	Ref string
	// Commit is the string value of the gh.git.commit key
	//
	// A Git commit, in the form of the hex encoding of the commit checksum.
	//
	// Type: string
	//
	// Examples:
	//   'e039abca90f1a9c965f28822094fffa5256e9d58'
	Commit string
	// ShortCommit is the string value of the gh.git.short_commit key
	//
	// Like `commit`, but in short form.
	//
	// Type: string
	//
	// Examples:
	//   '1d1b1f3'
	ShortCommit string
	// Path is the string value of the gh.git.path key
	//
	// Path to a file in a Git repository
	//
	// Type: string
	//
	// Examples:
	//   '.github/runtime.yml'
	Path string
}

// This document specifies common metadata specific to Git resources in user repositories.
var GhGit = ghGit{
	Ref:         "gh.git.ref",
	Commit:      "gh.git.commit",
	ShortCommit: "gh.git.short_commit",
	Path:        "gh.git.path",
}

// These attributes allow to report this unit of code and therefore to provide more context about
// where a span ended.
type ghCodeEnd struct {
	// Function is the string value of the gh.code.end.function key
	//
	// The method or function name, or equivalent (usually rightmost part of the code unit's name).
	//
	// Type: string
	//
	// Examples:
	//   'serveRequest'
	Function string
	// Namespace is the string value of the gh.code.end.namespace key
	//
	// The "namespace" within which `gh.code.end.function` is defined. Usually the qualified class or
	// module name, such that `gh.code.end.namespace` + some separator + the type name (if available)
	// form a unique identifier for the code unit.
	//
	// Type: string
	//
	// Examples:
	//   'com.example.MyHttpService'
	Namespace string
	// Filepath is the string value of the gh.code.end.filepath key
	//
	// The source code file name that identifies the code unit as uniquely as possible (preferably an
	// absolute file path).
	//
	// Type: string
	//
	// Examples:
	//   '/usr/local/MyApplication/content_root/app/index.php'
	Filepath string
	// Lineno is the string value of the gh.code.end.lineno key
	//
	// The line number in `gh.code.end.filepath` best representing the operation. It SHOULD point within
	// the code unit named in `gh.code.end.function`.
	//
	// Type: int
	//
	// Examples:
	//   42
	Lineno string
}

// These attributes allow to report this unit of code and therefore to provide more context about
// where a span ended.
var GhCodeEnd = ghCodeEnd{
	Function:  "gh.code.end.function",
	Namespace: "gh.code.end.namespace",
	Filepath:  "gh.code.end.filepath",
	Lineno:    "gh.code.end.lineno",
}

// This document specifies common exception metadata specific the copilot-telemetry-service
type ghCopilotTelemetry struct {
	// AppEnvironment is the string value of the gh.copilot_telemetry.app_environment key
	//
	// The value of the APP_ENV environment variable, which is apparently not the deployment environment
	// even though it has the same values.
	//
	// Type: string
	//
	// Examples:
	//   'unknown', 'production', 'development'
	AppEnvironment string
	// ItemsAccepted is the string value of the gh.copilot_telemetry.items_accepted key
	//
	// Number of items which have been accepted.
	//
	// Type: int
	//
	// Examples:
	//   5, 12
	ItemsAccepted string
	// ItemsReceived is the string value of the gh.copilot_telemetry.items_received key
	//
	// Number of items which have been received.
	//
	// Type: int
	//
	// Examples:
	//   8, 16
	ItemsReceived string
	// BadItemIndices is the string value of the gh.copilot_telemetry.bad_item_indices key
	//
	// Indices of the bad items.
	//
	// Type: int[]
	//
	// Examples:
	//   7, 42, 666], [100, 200, 300
	BadItemIndices string
	// BadItems is the string value of the gh.copilot_telemetry.bad_items key
	//
	// Number of bad items.
	//
	// Type: int
	//
	// Examples:
	//   3, 9
	BadItems string
	// TotalItems is the string value of the gh.copilot_telemetry.total_items key
	//
	// Total number of items.
	//
	// Type: int
	//
	// Examples:
	//   800, 1000000
	TotalItems string
	// PercentBadItems is the string value of the gh.copilot_telemetry.percent_bad_items key
	//
	// Bad items divided by total items.
	//
	// Type: double
	//
	// Examples:
	//   0.314, 0.662607
	PercentBadItems string
}

// This document specifies common exception metadata specific the copilot-telemetry-service
var GhCopilotTelemetry = ghCopilotTelemetry{
	AppEnvironment:  "gh.copilot_telemetry.app_environment",
	ItemsAccepted:   "gh.copilot_telemetry.items_accepted",
	ItemsReceived:   "gh.copilot_telemetry.items_received",
	BadItemIndices:  "gh.copilot_telemetry.bad_item_indices",
	BadItems:        "gh.copilot_telemetry.bad_items",
	TotalItems:      "gh.copilot_telemetry.total_items",
	PercentBadItems: "gh.copilot_telemetry.percent_bad_items",
}

// This document specifies common exception metadata specific to internal GitHub systems.
type ghException struct {
	// Rollup is the string value of the gh.exception.rollup key
	//
	// A fingerprint that uniquely identifies the exception and the callsite
	//
	// Type: string
	//
	// Examples:
	//   'ab08761803ea2dec3dc1817f108cd06a9de97b879fef0900e505f8336747e674'
	Rollup string
	// Project is the string value of the gh.exception.project key
	//
	// The category this exception belongs to.  In Sentry this will be the project name.  This is
	// commonly the application name, but some applications have multiple projects for different
	// purposes.
	//
	// Type: string
	//
	// Examples:
	//   'github', 'github-user', 'nines'
	Project string
}

// This document specifies common exception metadata specific to internal GitHub systems.
var GhException = ghException{
	Rollup:  "gh.exception.rollup",
	Project: "gh.exception.project",
}

// failbotg exposes an API that accepts exceptions and reports them to sentry and fluent-bit.
type ghFailbotg struct {
	// MessagePayloadBytes is the string value of the gh.failbotg.message.payload_bytes key
	//
	// The size of the message payload in bytes
	//
	// Type: int
	//
	// Examples:
	//   1024
	MessagePayloadBytes string
	// PayloadUncompressedBytes is the string value of the gh.failbotg.payload_uncompressed_bytes key
	//
	// The size of the uncompressed payload in bytes
	//
	// Type: int
	//
	// Examples:
	//   2048
	PayloadUncompressedBytes string
	// DestinationName is the string value of the gh.failbotg.destination.name key
	//
	// The name of the exception destination
	//
	// Type: string
	//
	// Examples:
	//   'fluent-bit', 'sentry'
	DestinationName string
	// MessageId is the string value of the gh.failbotg.message.id key
	//
	// the ID of the message
	//
	// Type: string
	//
	// Examples:
	//   'unique-id'
	MessageId string
}

// failbotg exposes an API that accepts exceptions and reports them to sentry and fluent-bit.
var GhFailbotg = ghFailbotg{
	MessagePayloadBytes:      "gh.failbotg.message.payload_bytes",
	PayloadUncompressedBytes: "gh.failbotg.payload_uncompressed_bytes",
	DestinationName:          "gh.failbotg.destination.name",
	MessageId:                "gh.failbotg.message.id",
}

// This document specifies common metadata specific to internal GitHub systems.
type gh struct {
	// RequestId is the string value of the gh.request_id key
	//
	// A received or generated GitHub Request-ID applicable to this trace.
	//
	// Type: string
	//
	// Requirement Level: Conditionally Required - If a client receives this attribute from an upstream request, then this attribute MUST be set to the received value. Otherwise, the client SHOULD generate a UUIDv4 for this attribute. Clients SHOULD NOT generate a new UUIDv4 in some circumstances, such as long-running background jobs which do not correlate to a single logical 'request' - or more generally, whenever a singular `github.request_id` would cause confusion. HTTP Clients SHOULD propagate this request in the `X-GitHub-RequestId` header, but that is otherwise out of scope for this document.
	//
	// Examples:
	//   'C661:2D45:1644B4E:2D936BB:60B6415F', 'a0e5b7e4-91da-4845-9914-9251d907e060'
	RequestId string
	// VisitorId is the string value of the gh.visitor_id key
	//
	// Analytics identifier, this is used for tracking users across different github.com domains. This
	// has also been referenced as octolytics_id in the past.
	//
	// Type: string
	//
	// Examples:
	//   'GH1.1.1234567899.9987654321'
	VisitorId string
	// Tenant is the string value of the gh.tenant key
	//
	// The GitHub Tenant applicable to this trace. In Proxima, this is the GitHub customer tenant. In
	// Dotcom this is 'dotcom'. In GHES, this is the customer account.
	//
	// Type: string
	//
	// Examples:
	//   'dotcom', 'contoso'
	Tenant string
	// OrgName is the string value of the gh.org.name key
	//
	// Name of a GitHub organization as returned by the [Organizations
	// API](https://docs.github.com/en/rest/reference/orgs#get-an-organization)
	//
	// Type: string
	//
	// Examples:
	//   'github', 'apache', 'tensorflow'
	OrgName string
	// OrgId is the string value of the gh.org.id key
	//
	// ID of a GitHub organization as returned by the [Organizations
	// API](https://docs.github.com/en/rest/reference/orgs#get-an-organization)
	//
	// Type: int
	OrgId string
	// RepoName is the string value of the gh.repo.name key
	//
	// Name of a GitHub repository as returned by the [Repositories
	// API](https://docs.github.com/en/rest/reference/repos#get-a-repository)
	//
	// Type: string
	//
	// Examples:
	//   'github', 'kafka', 'tensorflow'
	RepoName string
	// RepoId is the string value of the gh.repo.id key
	//
	// ID of a GitHub repository as returned by the [Repositories
	// API](https://docs.github.com/en/rest/reference/repos#get-a-repository)
	//
	// Type: int
	RepoId string
	// RepoNameWithOwner is the string value of the gh.repo.name_with_owner key
	//
	// Name of a GitHub repository with the owner as returned as `full_name` by the [Repositories
	// API](https://docs.github.com/en/rest/reference/repos#get-a-repository)"
	//
	// Type: string
	//
	// Examples:
	//   'github/github', 'apache/kafka', 'tensorflow/tensorflow'
	RepoNameWithOwner string
	// OwnerId is the string value of the gh.owner.id key
	//
	// ID of a GitHub repository owner. Can be an org or a user. Useful for systems that act on the
	// owner without a need to distinguish whether the owner is an org or a user.
	//
	// Type: int
	OwnerId string
	// OwnerLogin is the string value of the gh.owner.login key
	//
	// Name of a GitHub repository owner. Can be an org or a user. Useful for systems that act on the
	// owner without a need to distinguish whether the owner is an org or a user.
	//
	// Type: string
	//
	// Examples:
	//   'github', 'apache', 'tensorflow', 'aybabtme'
	OwnerLogin string
	// UserId is the string value of the gh.user.id key
	//
	// ID of a GitHub user as returned by the [Users
	// API](https://docs.github.com/en/rest/reference/users#get-a-single-user)
	//
	// Type: int
	UserId string
}

// This document specifies common metadata specific to internal GitHub systems.
var Gh = gh{
	RequestId:         "gh.request_id",
	VisitorId:         "gh.visitor_id",
	Tenant:            "gh.tenant",
	OrgName:           "gh.org.name",
	OrgId:             "gh.org.id",
	RepoName:          "gh.repo.name",
	RepoId:            "gh.repo.id",
	RepoNameWithOwner: "gh.repo.name_with_owner",
	OwnerId:           "gh.owner.id",
	OwnerLogin:        "gh.owner.login",
	UserId:            "gh.user.id",
}

// This document specifies common attribute names for generic operations that may be used in a
// GitHub service.  These may be used for jobs or any other operation where the status of the
// operation is important.
type ghOperation struct {
	// Name is the string value of the gh.operation.name key
	//
	// The name of the operation
	//
	// Type: string
	//
	// Examples:
	//   'email_sent', 'web_hook_delivered'
	//
	// Note:
	// The name of the operation should be meaningful in the context of the service.
	Name string
	// Duration is the string value of the gh.operation.duration key
	//
	// The duration of the operation in milliseconds.  This is the time between the start and end of the
	// operation.
	//
	// Type: double
	//
	// Examples:
	//   23.0, 0.23
	//
	// Note:
	// This may be a fractional amount to represent more accuracy than a whole amount of milliseconds
	// can represent.
	Duration string
}

// This document specifies common attribute names for generic operations that may be used in a
// GitHub service.  These may be used for jobs or any other operation where the status of the
// operation is important.
var GhOperation = ghOperation{
	Name:     "gh.operation.name",
	Duration: "gh.operation.duration",
}

// This document specifies common metadata specific to the Runtime product.
type ghRuntime struct {
	// DeployId is the string value of the gh.runtime.deploy_id key
	//
	// The ID of a Runtime deployment.
	//
	// Type: int
	DeployId string
}

// This document specifies common metadata specific to the Runtime product.
var GhRuntime = ghRuntime{
	DeployId: "gh.runtime.deploy_id",
}

// These are attributes specifically used in Twirp RPCs  traces
// (https://twitchtv.github.io/twirp/docs/spec_v5.html). These are generally used in automatic
// instrumentation that might be setup with github/github-telemetry-<lang> tracing needs for Twirp
// RPCs.
type ghTwirp struct {
	// Kind is the string value of the gh.twirp.kind key
	//
	// The kind of RPCs operation being performed.
	//
	// Type: Enum
	//
	// Requirement Level: Required
	//
	// Note:
	// The kind of RPCs to help determine what type of Twirp Hook is setup for the trace.
	Kind string
	// PackageName is the string value of the gh.twirp.package.name key
	//
	// The fully-qualified protobuf package name of the service handling the given context.
	//
	// Type: string
	//
	// Examples:
	//   'github.go_telemetry_go_examples_trace_twirp'
	//
	// Note:
	// If the package name not known, it will be empty (""). If the service comes from a proto file
	// that does not declare a package name, it will also be empty (""). Note that the protobuf
	// package name can be very different than the go package name; the two are unrelated. Also see
	// `twirp.PackageName` (https://pkg.go.dev/github.com/twitchtv/twirp?tab=doc#PackageName) for
	// more details.
	PackageName string
	// ServiceName is the string value of the gh.twirp.service.name key
	//
	// The name of the service handling the given context.
	//
	// Type: string
	//
	// Examples:
	//   'HelloWorldAPI'
	//
	// Note:
	// If the service name is not known, it returns an empty string (""). Also see
	// `twirp.ServiceName` (https://pkg.go.dev/github.com/twitchtv/twirp?tab=doc#ServiceName) for
	// more details.
	ServiceName string
}

// These are attributes specifically used in Twirp RPCs  traces
// (https://twitchtv.github.io/twirp/docs/spec_v5.html). These are generally used in automatic
// instrumentation that might be setup with github/github-telemetry-<lang> tracing needs for Twirp
// RPCs.
var GhTwirp = ghTwirp{
	Kind:        "gh.twirp.kind",
	PackageName: "gh.twirp.package.name",
	ServiceName: "gh.twirp.service.name",
}

// This document defines semantic conventions for HTTP client and server Spans.
type http struct {
	// Method is the string value of the http.method key
	//
	// HTTP request method.
	//
	// Type: string
	//
	// Requirement Level: Required
	//
	// Examples:
	//   'GET', 'POST', 'HEAD'
	Method string
	// StatusCode is the string value of the http.status_code key
	//
	// [HTTP response status code](https://tools.ietf.org/html/rfc7231#section-6).
	//
	// Type: int
	//
	// Requirement Level: Conditionally Required - If and only if one was received/sent.
	//
	// Examples:
	//   200
	StatusCode string
	// Flavor is the string value of the http.flavor key
	//
	// Kind of HTTP protocol used.
	//
	// Type: Enum
	//
	// Note:
	// If `net.transport` is not specified, it can be assumed to be `IP.TCP` except if `http.flavor`
	// is `QUIC`, in which case `IP.UDP` is assumed.
	Flavor string
	// UserAgent is the string value of the http.user_agent key
	//
	// Value of the [HTTP User-Agent](https://www.rfc-editor.org/rfc/rfc9110.html#field.user-agent)
	// header sent by the client.
	//
	// Type: string
	//
	// Examples:
	//   'CERN-LineMode/2.15 libwww/2.17b3'
	UserAgent string
	// RequestContentLength is the string value of the http.request_content_length key
	//
	// The size of the request payload body in bytes. This is the number of bytes transferred excluding
	// headers and is often, but not always, present as the [Content-Length](https://www.rfc-
	// editor.org/rfc/rfc9110.html#field.content-length) header. For requests using transport encoding,
	// this should be the compressed size.
	//
	// Type: int
	//
	// Examples:
	//   3495
	RequestContentLength string
	// ResponseContentLength is the string value of the http.response_content_length key
	//
	// The size of the response payload body in bytes. This is the number of bytes transferred excluding
	// headers and is often, but not always, present as the [Content-Length](https://www.rfc-
	// editor.org/rfc/rfc9110.html#field.content-length) header. For requests using transport encoding,
	// this should be the compressed size.
	//
	// Type: int
	//
	// Examples:
	//   3495
	ResponseContentLength string
}

// This document defines semantic conventions for HTTP client and server Spans.
var Http = http{
	Method:                "http.method",
	StatusCode:            "http.status_code",
	Flavor:                "http.flavor",
	UserAgent:             "http.user_agent",
	RequestContentLength:  "http.request_content_length",
	ResponseContentLength: "http.response_content_length",
}

// Semantic Convention for HTTP Client
type httpClient struct {
	// Url is the string value of the http.url key
	//
	// Full HTTP request URL in the form `scheme://host[:port]/path?query[#fragment]`. Usually the
	// fragment is not transmitted over HTTP, but if it is known, it should be included nevertheless.
	//
	// Type: string
	//
	// Requirement Level: Required
	//
	// Examples:
	//   'https://www.foo.bar/search?q=OpenTelemetry#SemConv'
	//
	// Note:
	// `http.url` MUST NOT contain credentials passed via URL in form of
	// `https://username:password@www.example.com/`. In such case the attribute's value should be
	// `https://www.example.com/`.
	Url string
	// RetryCount is the string value of the http.retry_count key
	//
	// The ordinal number of request re-sending attempt.
	//
	// Type: int
	//
	// Requirement Level: Recommended
	//
	// Examples:
	//   3
	RetryCount string
}

// Semantic Convention for HTTP Client
var HttpClient = httpClient{
	Url:        "http.url",
	RetryCount: "http.retry_count",
}

// Semantic Convention for HTTP Server
type httpServer struct {
	// Scheme is the string value of the http.scheme key
	//
	// The URI scheme identifying the used protocol.
	//
	// Type: string
	//
	// Requirement Level: Required
	//
	// Examples:
	//   'http', 'https'
	Scheme string
	// Target is the string value of the http.target key
	//
	// The full request target as passed in a HTTP request line or equivalent.
	//
	// Type: string
	//
	// Requirement Level: Required
	//
	// Examples:
	//   '/path/12314/?q=ddds'
	Target string
	// Route is the string value of the http.route key
	//
	// The matched route (path template in the format used by the respective server framework). See note
	// below
	//
	// Type: string
	//
	// Requirement Level: Conditionally Required - If and only if it's available
	//
	// Examples:
	//   '/users/:userID?', '{controller}/{action}/{id?}'
	//
	// Note:
	// 'http.route' MUST NOT be populated when this is not supported by the HTTP server framework as
	// the route attribute should have low-cardinality and the URI path can NOT substitute it.
	Route string
	// ClientIp is the string value of the http.client_ip key
	//
	// The IP address of the original client behind all proxies, if known (e.g. from [X-Forwarded-
	// For](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/X-Forwarded-For)).
	//
	// Type: string
	//
	// Examples:
	//   '83.164.160.102'
	//
	// Note:
	// This is not necessarily the same as `net.sock.peer.addr`, which would identify the network-
	// level peer, which may be a proxy.
	//
	// This attribute should be set when a source of information different from the one used for
	// `net.sock.peer.addr`, is available even if that other source just confirms the same value as
	// `net.sock.peer.addr`. Rationale: For `net.sock.peer.addr`, one typically does not know if it
	// comes from a proxy, reverse proxy, or the actual client. Setting `http.client_ip` when it's
	// the same as `net.sock.peer.addr` means that one is at least somewhat confident that the
	// address is not that of the closest proxy.
	ClientIp string
}

// Semantic Convention for HTTP Server
var HttpServer = httpServer{
	Scheme:   "http.scheme",
	Target:   "http.target",
	Route:    "http.route",
	ClientIp: "http.client_ip",
}

// The `aws` conventions apply to operations using the AWS SDK. They map request or response
// parameters in AWS SDK API calls to attributes on a Span. The conventions have been collected over
// time based on feedback from AWS users of tracing and will continue to evolve as new interesting
// conventions are found.
// Some descriptions are also provided for populating general OpenTelemetry semantic conventions
// based on these APIs.
type aws struct {
}

// The `aws` conventions apply to operations using the AWS SDK. They map request or response
// parameters in AWS SDK API calls to attributes on a Span. The conventions have been collected over
// time based on feedback from AWS users of tracing and will continue to evolve as new interesting
// conventions are found.
// Some descriptions are also provided for populating general OpenTelemetry semantic conventions
// based on these APIs.
var Aws = aws{}

// Attributes always filled for all DynamoDB request types.
type dynamodbAll struct {
}

// Attributes always filled for all DynamoDB request types.
var DynamodbAll = dynamodbAll{}

// Attributes that exist for multiple DynamoDB request types.
type dynamodbShared struct {
	// TableNames is the string value of the aws.dynamodb.table_names key
	//
	// The keys in the `RequestItems` object field.
	//
	// Type: string[]
	//
	// Examples:
	//   'Users', 'Cats'
	TableNames string
	// ConsumedCapacity is the string value of the aws.dynamodb.consumed_capacity key
	//
	// The JSON-serialized value of each item in the `ConsumedCapacity` response field.
	//
	// Type: string[]
	//
	// Examples:
	//   '{ "CapacityUnits": number, "GlobalSecondaryIndexes": { "string" : { "CapacityUnits": number,
	// "ReadCapacityUnits": number, "WriteCapacityUnits": number } }, "LocalSecondaryIndexes": {
	// "string" : { "CapacityUnits": number, "ReadCapacityUnits": number, "WriteCapacityUnits": number }
	// }, "ReadCapacityUnits": number, "Table": { "CapacityUnits": number, "ReadCapacityUnits": number,
	// "WriteCapacityUnits": number }, "TableName": "string", "WriteCapacityUnits": number }'
	ConsumedCapacity string
	// ItemCollectionMetrics is the string value of the aws.dynamodb.item_collection_metrics key
	//
	// The JSON-serialized value of the `ItemCollectionMetrics` response field.
	//
	// Type: string
	//
	// Examples:
	//   '{ "string" : [ { "ItemCollectionKey": { "string" : { "B": blob, "BOOL": boolean, "BS": [ blob ],
	// "L": [ "AttributeValue" ], "M": { "string" : "AttributeValue" }, "N": "string", "NS": [ "string"
	// ], "NULL": boolean, "S": "string", "SS": [ "string" ] } }, "SizeEstimateRangeGB": [ number ] } ]
	// }'
	ItemCollectionMetrics string
	// ProvisionedReadCapacity is the string value of the aws.dynamodb.provisioned_read_capacity key
	//
	// The value of the `ProvisionedThroughput.ReadCapacityUnits` request parameter.
	//
	// Type: double
	//
	// Examples:
	//   1.0, 2.0
	ProvisionedReadCapacity string
	// ProvisionedWriteCapacity is the string value of the aws.dynamodb.provisioned_write_capacity key
	//
	// The value of the `ProvisionedThroughput.WriteCapacityUnits` request parameter.
	//
	// Type: double
	//
	// Examples:
	//   1.0, 2.0
	ProvisionedWriteCapacity string
	// ConsistentRead is the string value of the aws.dynamodb.consistent_read key
	//
	// The value of the `ConsistentRead` request parameter.
	//
	// Type: boolean
	ConsistentRead string
	// Projection is the string value of the aws.dynamodb.projection key
	//
	// The value of the `ProjectionExpression` request parameter.
	//
	// Type: string
	//
	// Examples:
	//   'Title', 'Title, Price, Color', 'Title, Description, RelatedItems, ProductReviews'
	Projection string
	// Limit is the string value of the aws.dynamodb.limit key
	//
	// The value of the `Limit` request parameter.
	//
	// Type: int
	//
	// Examples:
	//   10
	Limit string
	// AttributesToGet is the string value of the aws.dynamodb.attributes_to_get key
	//
	// The value of the `AttributesToGet` request parameter.
	//
	// Type: string[]
	//
	// Examples:
	//   'lives', 'id'
	AttributesToGet string
	// IndexName is the string value of the aws.dynamodb.index_name key
	//
	// The value of the `IndexName` request parameter.
	//
	// Type: string
	//
	// Examples:
	//   'name_to_group'
	IndexName string
	// Select is the string value of the aws.dynamodb.select key
	//
	// The value of the `Select` request parameter.
	//
	// Type: string
	//
	// Examples:
	//   'ALL_ATTRIBUTES', 'COUNT'
	Select string
}

// Attributes that exist for multiple DynamoDB request types.
var DynamodbShared = dynamodbShared{
	TableNames:               "aws.dynamodb.table_names",
	ConsumedCapacity:         "aws.dynamodb.consumed_capacity",
	ItemCollectionMetrics:    "aws.dynamodb.item_collection_metrics",
	ProvisionedReadCapacity:  "aws.dynamodb.provisioned_read_capacity",
	ProvisionedWriteCapacity: "aws.dynamodb.provisioned_write_capacity",
	ConsistentRead:           "aws.dynamodb.consistent_read",
	Projection:               "aws.dynamodb.projection",
	Limit:                    "aws.dynamodb.limit",
	AttributesToGet:          "aws.dynamodb.attributes_to_get",
	IndexName:                "aws.dynamodb.index_name",
	Select:                   "aws.dynamodb.select",
}

// DynamoDB.BatchGetItem
type dynamodbBatchgetitem struct {
}

// DynamoDB.BatchGetItem
var DynamodbBatchgetitem = dynamodbBatchgetitem{}

// DynamoDB.BatchWriteItem
type dynamodbBatchwriteitem struct {
}

// DynamoDB.BatchWriteItem
var DynamodbBatchwriteitem = dynamodbBatchwriteitem{}

// DynamoDB.CreateTable
type dynamodbCreatetable struct {
	// GlobalSecondaryIndexes is the string value of the aws.dynamodb.global_secondary_indexes key
	//
	// The JSON-serialized value of each item of the `GlobalSecondaryIndexes` request field
	//
	// Type: string[]
	//
	// Examples:
	//   '{ "IndexName": "string", "KeySchema": [ { "AttributeName": "string", "KeyType": "string" } ],
	// "Projection": { "NonKeyAttributes": [ "string" ], "ProjectionType": "string" },
	// "ProvisionedThroughput": { "ReadCapacityUnits": number, "WriteCapacityUnits": number } }'
	GlobalSecondaryIndexes string
	// LocalSecondaryIndexes is the string value of the aws.dynamodb.local_secondary_indexes key
	//
	// The JSON-serialized value of each item of the `LocalSecondaryIndexes` request field.
	//
	// Type: string[]
	//
	// Examples:
	//   '{ "IndexArn": "string", "IndexName": "string", "IndexSizeBytes": number, "ItemCount": number,
	// "KeySchema": [ { "AttributeName": "string", "KeyType": "string" } ], "Projection": {
	// "NonKeyAttributes": [ "string" ], "ProjectionType": "string" } }'
	LocalSecondaryIndexes string
}

// DynamoDB.CreateTable
var DynamodbCreatetable = dynamodbCreatetable{
	GlobalSecondaryIndexes: "aws.dynamodb.global_secondary_indexes",
	LocalSecondaryIndexes:  "aws.dynamodb.local_secondary_indexes",
}

// DynamoDB.DeleteItem
type dynamodbDeleteitem struct {
}

// DynamoDB.DeleteItem
var DynamodbDeleteitem = dynamodbDeleteitem{}

// DynamoDB.DeleteTable
type dynamodbDeletetable struct {
}

// DynamoDB.DeleteTable
var DynamodbDeletetable = dynamodbDeletetable{}

// DynamoDB.DescribeTable
type dynamodbDescribetable struct {
}

// DynamoDB.DescribeTable
var DynamodbDescribetable = dynamodbDescribetable{}

// DynamoDB.GetItem
type dynamodbGetitem struct {
}

// DynamoDB.GetItem
var DynamodbGetitem = dynamodbGetitem{}

// DynamoDB.ListTables
type dynamodbListtables struct {
	// ExclusiveStartTable is the string value of the aws.dynamodb.exclusive_start_table key
	//
	// The value of the `ExclusiveStartTableName` request parameter.
	//
	// Type: string
	//
	// Examples:
	//   'Users', 'CatsTable'
	ExclusiveStartTable string
	// TableCount is the string value of the aws.dynamodb.table_count key
	//
	// The the number of items in the `TableNames` response parameter.
	//
	// Type: int
	//
	// Examples:
	//   20
	TableCount string
}

// DynamoDB.ListTables
var DynamodbListtables = dynamodbListtables{
	ExclusiveStartTable: "aws.dynamodb.exclusive_start_table",
	TableCount:          "aws.dynamodb.table_count",
}

// DynamoDB.PutItem
type dynamodbPutitem struct {
}

// DynamoDB.PutItem
var DynamodbPutitem = dynamodbPutitem{}

// DynamoDB.Query
type dynamodbQuery struct {
	// ScanForward is the string value of the aws.dynamodb.scan_forward key
	//
	// The value of the `ScanIndexForward` request parameter.
	//
	// Type: boolean
	ScanForward string
}

// DynamoDB.Query
var DynamodbQuery = dynamodbQuery{
	ScanForward: "aws.dynamodb.scan_forward",
}

// DynamoDB.Scan
type dynamodbScan struct {
	// Segment is the string value of the aws.dynamodb.segment key
	//
	// The value of the `Segment` request parameter.
	//
	// Type: int
	//
	// Examples:
	//   10
	Segment string
	// TotalSegments is the string value of the aws.dynamodb.total_segments key
	//
	// The value of the `TotalSegments` request parameter.
	//
	// Type: int
	//
	// Examples:
	//   100
	TotalSegments string
	// Count is the string value of the aws.dynamodb.count key
	//
	// The value of the `Count` response parameter.
	//
	// Type: int
	//
	// Examples:
	//   10
	Count string
	// ScannedCount is the string value of the aws.dynamodb.scanned_count key
	//
	// The value of the `ScannedCount` response parameter.
	//
	// Type: int
	//
	// Examples:
	//   50
	ScannedCount string
}

// DynamoDB.Scan
var DynamodbScan = dynamodbScan{
	Segment:       "aws.dynamodb.segment",
	TotalSegments: "aws.dynamodb.total_segments",
	Count:         "aws.dynamodb.count",
	ScannedCount:  "aws.dynamodb.scanned_count",
}

// DynamoDB.UpdateItem
type dynamodbUpdateitem struct {
}

// DynamoDB.UpdateItem
var DynamodbUpdateitem = dynamodbUpdateitem{}

// DynamoDB.UpdateTable
type dynamodbUpdatetable struct {
	// AttributeDefinitions is the string value of the aws.dynamodb.attribute_definitions key
	//
	// The JSON-serialized value of each item in the `AttributeDefinitions` request field.
	//
	// Type: string[]
	//
	// Examples:
	//   '{ "AttributeName": "string", "AttributeType": "string" }'
	AttributeDefinitions string
	// GlobalSecondaryIndexUpdates is the string value of the aws.dynamodb.global_secondary_index_updates key
	//
	// The JSON-serialized value of each item in the the `GlobalSecondaryIndexUpdates` request field.
	//
	// Type: string[]
	//
	// Examples:
	//   '{ "Create": { "IndexName": "string", "KeySchema": [ { "AttributeName": "string", "KeyType":
	// "string" } ], "Projection": { "NonKeyAttributes": [ "string" ], "ProjectionType": "string" },
	// "ProvisionedThroughput": { "ReadCapacityUnits": number, "WriteCapacityUnits": number } }'
	GlobalSecondaryIndexUpdates string
}

// DynamoDB.UpdateTable
var DynamodbUpdatetable = dynamodbUpdatetable{
	AttributeDefinitions:        "aws.dynamodb.attribute_definitions",
	GlobalSecondaryIndexUpdates: "aws.dynamodb.global_secondary_index_updates",
}

// This document defines semantic conventions to apply when instrumenting the GraphQL
// implementation. They map GraphQL operations to attributes on a Span.
type graphql struct {
	// OperationName is the string value of the graphql.operation.name key
	//
	// The name of the operation being executed.
	//
	// Type: string
	//
	// Examples:
	//   'findBookById'
	OperationName string
	// OperationType is the string value of the graphql.operation.type key
	//
	// The type of the operation being executed.
	//
	// Type: Enum
	//
	// Examples:
	//   'query', 'mutation', 'subscription'
	OperationType string
	// Document is the string value of the graphql.document key
	//
	// The GraphQL document being executed.
	//
	// Type: string
	//
	// Examples:
	//   'query findBookById { bookById(id: ?) { name } }'
	//
	// Note:
	// The value may be sanitized to exclude sensitive information.
	Document string
}

// This document defines semantic conventions to apply when instrumenting the GraphQL
// implementation. They map GraphQL operations to attributes on a Span.
var Graphql = graphql{
	OperationName: "graphql.operation.name",
	OperationType: "graphql.operation.type",
	Document:      "graphql.document",
}

// This document defines the attributes used in messaging systems.
type messaging struct {
	// System is the string value of the messaging.system key
	//
	// A string identifying the messaging system.
	//
	// Type: string
	//
	// Requirement Level: Required
	//
	// Examples:
	//   'kafka', 'rabbitmq', 'rocketmq', 'activemq', 'AmazonSQS'
	System string
	// Destination is the string value of the messaging.destination key
	//
	// The message destination name. This might be equal to the span name but is required nevertheless.
	//
	// Type: string
	//
	// Requirement Level: Required
	//
	// Examples:
	//   'MyQueue', 'MyTopic'
	Destination string
	// DestinationKind is the string value of the messaging.destination_kind key
	//
	// The kind of message destination
	//
	// Type: Enum
	//
	// Requirement Level: Conditionally Required - If the message destination is either a `queue` or `topic`.
	DestinationKind string
	// TempDestination is the string value of the messaging.temp_destination key
	//
	// A boolean that is true if the message destination is temporary.
	//
	// Type: boolean
	//
	// Requirement Level: Conditionally Required - If value is `true`. When missing, the value is assumed to be `false`.
	TempDestination string
	// Protocol is the string value of the messaging.protocol key
	//
	// The name of the transport protocol.
	//
	// Type: string
	//
	// Examples:
	//   'AMQP', 'MQTT'
	Protocol string
	// ProtocolVersion is the string value of the messaging.protocol_version key
	//
	// The version of the transport protocol.
	//
	// Type: string
	//
	// Examples:
	//   '0.9.1'
	ProtocolVersion string
	// Url is the string value of the messaging.url key
	//
	// Connection string.
	//
	// Type: string
	//
	// Examples:
	//   'tibjmsnaming://localhost:7222', 'https://queue.amazonaws.com/80398EXAMPLE/MyQueue'
	Url string
	// MessageId is the string value of the messaging.message_id key
	//
	// A value used by the messaging system as an identifier for the message, represented as a string.
	//
	// Type: string
	//
	// Examples:
	//   '452a7c7c7c7048c2f887f61572b18fc2'
	MessageId string
	// ConversationId is the string value of the messaging.conversation_id key
	//
	// The [conversation ID](#conversations) identifying the conversation to which the message belongs,
	// represented as a string. Sometimes called "Correlation ID".
	//
	// Type: string
	//
	// Examples:
	//   'MyConversationId'
	ConversationId string
	// MessagePayloadSizeBytes is the string value of the messaging.message_payload_size_bytes key
	//
	// The (uncompressed) size of the message payload in bytes. Also use this attribute if it is unknown
	// whether the compressed or uncompressed payload size is reported.
	//
	// Type: int
	//
	// Examples:
	//   2738
	MessagePayloadSizeBytes string
	// MessagePayloadCompressedSizeBytes is the string value of the messaging.message_payload_compressed_size_bytes key
	//
	// The compressed size of the message payload in bytes.
	//
	// Type: int
	//
	// Examples:
	//   2048
	MessagePayloadCompressedSizeBytes string
}

// This document defines the attributes used in messaging systems.
var Messaging = messaging{
	System:                            "messaging.system",
	Destination:                       "messaging.destination",
	DestinationKind:                   "messaging.destination_kind",
	TempDestination:                   "messaging.temp_destination",
	Protocol:                          "messaging.protocol",
	ProtocolVersion:                   "messaging.protocol_version",
	Url:                               "messaging.url",
	MessageId:                         "messaging.message_id",
	ConversationId:                    "messaging.conversation_id",
	MessagePayloadSizeBytes:           "messaging.message_payload_size_bytes",
	MessagePayloadCompressedSizeBytes: "messaging.message_payload_compressed_size_bytes",
}

// Semantic convention for producers of messages sent to a messaging systems.
type messagingProducer struct {
}

// Semantic convention for producers of messages sent to a messaging systems.
var MessagingProducer = messagingProducer{}

// Semantic convention for clients of messaging systems that produce messages and synchronously wait
// for responses.
type messagingProducerSynchronous struct {
}

// Semantic convention for clients of messaging systems that produce messages and synchronously wait
// for responses.
var MessagingProducerSynchronous = messagingProducerSynchronous{}

// Semantic convention for a consumer of messages received from a messaging system
type messagingConsumer struct {
	// Operation is the string value of the messaging.operation key
	//
	// A string identifying the kind of message consumption as defined in the [Operation
	// names](#operation-names) section above. If the operation is "send", this attribute MUST NOT be
	// set, since the operation can be inferred from the span kind in that case.
	//
	// Type: Enum
	Operation string
	// ConsumerId is the string value of the messaging.consumer_id key
	//
	// The identifier for the consumer receiving a message. For Kafka, set it to
	// `{messaging.kafka.consumer_group} - {messaging.kafka.client_id}`, if both are present, or only
	// `messaging.kafka.consumer_group`. For brokers, such as RabbitMQ and Artemis, set it to the
	// `client_id` of the client consuming the message.
	//
	// Type: string
	//
	// Examples:
	//   'mygroup - client-6'
	ConsumerId string
}

// Semantic convention for a consumer of messages received from a messaging system
var MessagingConsumer = messagingConsumer{
	Operation:  "messaging.operation",
	ConsumerId: "messaging.consumer_id",
}

// Semantic convention for servers that consume messages received from messaging systems and always
// send back replies directed to the producers of these messages.
type messagingConsumerSynchronous struct {
}

// Semantic convention for servers that consume messages received from messaging systems and always
// send back replies directed to the producers of these messages.
var MessagingConsumerSynchronous = messagingConsumerSynchronous{}

// Attributes for RabbitMQ
type messagingRabbitmq struct {
	// RoutingKey is the string value of the messaging.rabbitmq.routing_key key
	//
	// RabbitMQ message routing key.
	//
	// Type: string
	//
	// Requirement Level: Conditionally Required - If not empty.
	//
	// Examples:
	//   'myKey'
	RoutingKey string
}

// Attributes for RabbitMQ
var MessagingRabbitmq = messagingRabbitmq{
	RoutingKey: "messaging.rabbitmq.routing_key",
}

// Attributes for Apache Kafka
type messagingKafka struct {
	// MessageKey is the string value of the messaging.kafka.message_key key
	//
	// Message keys in Kafka are used for grouping alike messages to ensure they're processed on the
	// same partition. They differ from `messaging.message_id` in that they're not unique. If the key is
	// `null`, the attribute MUST NOT be set.
	//
	// Type: string
	//
	// Examples:
	//   'myKey'
	//
	// Note:
	// If the key type is not string, it's string representation has to be supplied for the
	// attribute. If the key has no unambiguous, canonical string form, don't include its value.
	MessageKey string
	// ConsumerGroup is the string value of the messaging.kafka.consumer_group key
	//
	// Name of the Kafka Consumer Group that is handling the message. Only applies to consumers, not
	// producers.
	//
	// Type: string
	//
	// Examples:
	//   'my-group'
	ConsumerGroup string
	// ClientId is the string value of the messaging.kafka.client_id key
	//
	// Client Id for the Consumer or Producer that is handling the message.
	//
	// Type: string
	//
	// Examples:
	//   'client-5'
	ClientId string
	// Partition is the string value of the messaging.kafka.partition key
	//
	// Partition the message is sent to.
	//
	// Type: int
	//
	// Examples:
	//   2
	Partition string
	// Tombstone is the string value of the messaging.kafka.tombstone key
	//
	// A boolean that is true if the message is a tombstone.
	//
	// Type: boolean
	//
	// Requirement Level: Conditionally Required - If value is `true`. When missing, the value is assumed to be `false`.
	Tombstone string
}

// Attributes for Apache Kafka
var MessagingKafka = messagingKafka{
	MessageKey:    "messaging.kafka.message_key",
	ConsumerGroup: "messaging.kafka.consumer_group",
	ClientId:      "messaging.kafka.client_id",
	Partition:     "messaging.kafka.partition",
	Tombstone:     "messaging.kafka.tombstone",
}

// Attributes for Apache RocketMQ
type messagingRocketmq struct {
	// Namespace is the string value of the messaging.rocketmq.namespace key
	//
	// Namespace of RocketMQ resources, resources in different namespaces are individual.
	//
	// Type: string
	//
	// Requirement Level: Required
	//
	// Examples:
	//   'myNamespace'
	Namespace string
	// ClientGroup is the string value of the messaging.rocketmq.client_group key
	//
	// Name of the RocketMQ producer/consumer group that is handling the message. The client type is
	// identified by the SpanKind.
	//
	// Type: string
	//
	// Requirement Level: Required
	//
	// Examples:
	//   'myConsumerGroup'
	ClientGroup string
	// ClientId is the string value of the messaging.rocketmq.client_id key
	//
	// The unique identifier for each client.
	//
	// Type: string
	//
	// Requirement Level: Required
	//
	// Examples:
	//   'myhost@8742@s8083jm'
	ClientId string
	// MessageType is the string value of the messaging.rocketmq.message_type key
	//
	// Type of message.
	//
	// Type: Enum
	MessageType string
	// MessageTag is the string value of the messaging.rocketmq.message_tag key
	//
	// The secondary classifier of message besides topic.
	//
	// Type: string
	//
	// Examples:
	//   'tagA'
	MessageTag string
	// MessageKeys is the string value of the messaging.rocketmq.message_keys key
	//
	// Key(s) of message, another way to mark message besides message id.
	//
	// Type: string[]
	//
	// Examples:
	//   'keyA', 'keyB'
	MessageKeys string
	// ConsumptionModel is the string value of the messaging.rocketmq.consumption_model key
	//
	// Model of message consumption. This only applies to consumer spans.
	//
	// Type: Enum
	ConsumptionModel string
}

// Attributes for Apache RocketMQ
var MessagingRocketmq = messagingRocketmq{
	Namespace:        "messaging.rocketmq.namespace",
	ClientGroup:      "messaging.rocketmq.client_group",
	ClientId:         "messaging.rocketmq.client_id",
	MessageType:      "messaging.rocketmq.message_type",
	MessageTag:       "messaging.rocketmq.message_tag",
	MessageKeys:      "messaging.rocketmq.message_keys",
	ConsumptionModel: "messaging.rocketmq.consumption_model",
}

// This document defines semantic conventions for remote procedure calls.
type rpc struct {
	// System is the string value of the rpc.system key
	//
	// A string identifying the remoting system. See below for a list of well-known identifiers.
	//
	// Type: Enum
	//
	// Requirement Level: Required
	System string
	// Service is the string value of the rpc.service key
	//
	// The full (logical) name of the service being called, including its package name, if applicable.
	//
	// Type: string
	//
	// Requirement Level: Recommended
	//
	// Examples:
	//   'myservice.EchoService'
	//
	// Note:
	// This is the logical name of the service from the RPC interface perspective, which can be
	// different from the name of any implementing class. The `code.namespace` attribute may be used
	// to store the latter (despite the attribute name, it may include a class name; e.g., class with
	// method actually executing the call on the server side, RPC client stub class on the client
	// side).
	Service string
	// Method is the string value of the rpc.method key
	//
	// The name of the (logical) method being called, must be equal to the $method part in the span
	// name.
	//
	// Type: string
	//
	// Requirement Level: Recommended
	//
	// Examples:
	//   'exampleMethod'
	//
	// Note:
	// This is the logical name of the method from the RPC interface perspective, which can be
	// different from the name of any implementing method/function. The `code.function` attribute may
	// be used to store the latter (e.g., method actually executing the call on the server side, RPC
	// client stub method on the client side).
	Method string
}

// This document defines semantic conventions for remote procedure calls.
var Rpc = rpc{
	System:  "rpc.system",
	Service: "rpc.service",
	Method:  "rpc.method",
}

// Semantic Convention for RPC server spans
type rpcServer struct {
}

// Semantic Convention for RPC server spans
var RpcServer = rpcServer{}

// Tech-specific attributes for gRPC.
type rpcGrpc struct {
	// StatusCode is the string value of the rpc.grpc.status_code key
	//
	// The [numeric status code](https://github.com/grpc/grpc/blob/v1.33.2/doc/statuscodes.md) of the
	// gRPC request.
	//
	// Type: Enum
	//
	// Requirement Level: Required
	StatusCode string
}

// Tech-specific attributes for gRPC.
var RpcGrpc = rpcGrpc{
	StatusCode: "rpc.grpc.status_code",
}

// Tech-specific attributes for [JSON RPC](https://www.jsonrpc.org/).
type rpcJsonrpc struct {
	// Version is the string value of the rpc.jsonrpc.version key
	//
	// Protocol version as in `jsonrpc` property of request/response. Since JSON-RPC 1.0 does not
	// specify this, the value can be omitted.
	//
	// Type: string
	//
	// Requirement Level: Conditionally Required - If other than the default version (`1.0`)
	//
	// Examples:
	//   '2.0', '1.0'
	Version string
	// RequestId is the string value of the rpc.jsonrpc.request_id key
	//
	// `id` property of request or response. Since protocol allows id to be int, string, `null` or
	// missing (for notifications), value is expected to be cast to string for simplicity. Use empty
	// string in case of `null` value. Omit entirely if this is a notification.
	//
	// Type: string
	//
	// Examples:
	//   '10', 'request-7', ''
	RequestId string
	// ErrorCode is the string value of the rpc.jsonrpc.error_code key
	//
	// `error.code` property of response if it is an error response.
	//
	// Type: int
	//
	// Requirement Level: Conditionally Required - If response is not successful.
	//
	// Examples:
	//   -32700, 100
	ErrorCode string
	// ErrorMessage is the string value of the rpc.jsonrpc.error_message key
	//
	// `error.message` property of response if it is an error response.
	//
	// Type: string
	//
	// Examples:
	//   'Parse error', 'User already exists'
	ErrorMessage string
}

// Tech-specific attributes for [JSON RPC](https://www.jsonrpc.org/).
var RpcJsonrpc = rpcJsonrpc{
	Version:      "rpc.jsonrpc.version",
	RequestId:    "rpc.jsonrpc.request_id",
	ErrorCode:    "rpc.jsonrpc.error_code",
	ErrorMessage: "rpc.jsonrpc.error_message",
}

// RPC received/sent message.
type rpcMessage struct {
	// Type is the string value of the message.type key
	//
	// Whether this is a received or sent message.
	//
	// Type: Enum
	Type string
	// Id is the string value of the message.id key
	//
	// MUST be calculated as two different counters starting from `1` one for sent messages and one for
	// received message.
	//
	// Type: int
	//
	// Note:
	// This way we guarantee that the values will be consistent between different implementations.
	Id string
	// CompressedSize is the string value of the message.compressed_size key
	//
	// Compressed size of the message in bytes.
	//
	// Type: int
	CompressedSize string
	// UncompressedSize is the string value of the message.uncompressed_size key
	//
	// Uncompressed size of the message in bytes.
	//
	// Type: int
	UncompressedSize string
}

// RPC received/sent message.
var RpcMessage = rpcMessage{
	Type:             "message.type",
	Id:               "message.id",
	CompressedSize:   "message.compressed_size",
	UncompressedSize: "message.uncompressed_size",
}
