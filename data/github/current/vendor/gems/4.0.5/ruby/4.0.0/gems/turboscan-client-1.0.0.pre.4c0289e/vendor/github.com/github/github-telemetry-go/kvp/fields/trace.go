// DO NOT EDIT MANUALLY!!! This is generated code from:
// Repo:     github/github-semantic-conventions
// Script:   script/update-go
// Template: go/templates/fields.j2

// Deprecated: services should use the semantic conventions directly
// As of https://github.com/github/observability/pull/3479 this code will no
// longer be kept up to date with the latest conventions
package fields

import (
	"github.com/github/github-telemetry-go/kvp"
)

// Span attributes used by AWS Lambda (in addition to general `faas` attributes).
type awsLambda struct {
	// InvokedArn returns a kvp.Field with the aws.lambda.invoked_arn key and the value you provide.
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
	InvokedArn func(value string) kvp.Field
}

// Span attributes used by AWS Lambda (in addition to general `faas` attributes).
var AwsLambda = awsLambda{
	InvokedArn: func(value string) kvp.Field {
		return kvp.String("aws.lambda.invoked_arn", value)
	},
}

// This document specifies common metadata specific to Azure resources provisioned on behalf of
// users. For  Azure resources provisioned as GitHub infrastructure, use the `github-infra`
// conventions..
type ghAzure struct {
	// Location returns a kvp.Field with the gh.azure.location key and the value you provide.
	//
	// An Azure location.
	//
	// Type: string
	//
	// Examples:
	//   'West US', 'East US'
	Location func(value string) kvp.Field
}

// This document specifies common metadata specific to Azure resources provisioned on behalf of
// users. For  Azure resources provisioned as GitHub infrastructure, use the `github-infra`
// conventions..
var GhAzure = ghAzure{
	Location: func(value string) kvp.Field {
		return kvp.String("gh.azure.location", value)
	},
}

// This document defines attributes for CloudEvents. CloudEvents is a specification on how to define
// event data in a standard way. These attributes can be attached to spans when performing
// operations with CloudEvents, regardless of the protocol being used.
type cloudevents struct {
	// EventId returns a kvp.Field with the cloudevents.event_id key and the value you provide.
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
	EventId func(value string) kvp.Field

	// EventSource returns a kvp.Field with the cloudevents.event_source key and the value you provide.
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
	EventSource func(value string) kvp.Field

	// EventSpecVersion returns a kvp.Field with the cloudevents.event_spec_version key and the value you provide.
	//
	// The [version of the CloudEvents
	// specification](https://github.com/cloudevents/spec/blob/v1.0.2/cloudevents/spec.md#specversion)
	// which the event uses.
	//
	// Type: string
	//
	// Examples:
	//   '1.0'
	EventSpecVersion func(value string) kvp.Field

	// EventType returns a kvp.Field with the cloudevents.event_type key and the value you provide.
	//
	// The [event_type](https://github.com/cloudevents/spec/blob/v1.0.2/cloudevents/spec.md#type)
	// contains a value describing the type of event related to the originating occurrence.
	//
	// Type: string
	//
	// Examples:
	//   'com.github.pull_request.opened', 'com.example.object.deleted.v2'
	EventType func(value string) kvp.Field

	// EventSubject returns a kvp.Field with the cloudevents.event_subject key and the value you provide.
	//
	// The [subject](https://github.com/cloudevents/spec/blob/v1.0.2/cloudevents/spec.md#subject) of the
	// event in the context of the event producer (identified by source).
	//
	// Type: string
	//
	// Examples:
	//   'mynewfile.jpg'
	EventSubject func(value string) kvp.Field
}

// This document defines attributes for CloudEvents. CloudEvents is a specification on how to define
// event data in a standard way. These attributes can be attached to spans when performing
// operations with CloudEvents, regardless of the protocol being used.
var Cloudevents = cloudevents{
	EventId: func(value string) kvp.Field {
		return kvp.String("cloudevents.event_id", value)
	},

	EventSource: func(value string) kvp.Field {
		return kvp.String("cloudevents.event_source", value)
	},

	EventSpecVersion: func(value string) kvp.Field {
		return kvp.String("cloudevents.event_spec_version", value)
	},

	EventType: func(value string) kvp.Field {
		return kvp.String("cloudevents.event_type", value)
	},

	EventSubject: func(value string) kvp.Field {
		return kvp.String("cloudevents.event_subject", value)
	},
}

// This document defines semantic conventions for the OpenTracing Shim
type opentracing struct {

	// RefType struct
	//
	// Parent-child Reference type
	//
	// Type: Enum
	//
	// Note:
	// The causal relationship between a child Span and a parent Span.
	RefType struct {
		// ChildOf is a kvp.Field with key "opentracing.ref_type" and value "child_of"
		//
		// The parent Span depends on the child Span in some capacity
		ChildOf kvp.Field

		// FollowsFrom is a kvp.Field with key "opentracing.ref_type" and value "follows_from"
		//
		// The parent Span does not depend in any way on the result of the child Span
		FollowsFrom kvp.Field
	}
}

// This document defines semantic conventions for the OpenTracing Shim
var Opentracing = opentracing{
	RefType: struct {
		ChildOf     kvp.Field
		FollowsFrom kvp.Field
	}{
		ChildOf:     kvp.String("opentracing.ref_type", "child_of"),
		FollowsFrom: kvp.String("opentracing.ref_type", "follows_from"),
	},
}

// This document defines the attributes used to perform database client calls.
type db struct {

	// System struct
	//
	// An identifier for the database management system (DBMS) product being used. See below for a list
	// of well-known identifiers.
	//
	// Type: Enum
	//
	// Requirement Level: Required
	System struct {
		// OtherSql is a kvp.Field with key "db.system" and value "other_sql"
		//
		// Some other SQL database. Fallback only. See notes
		OtherSql kvp.Field

		// Mssql is a kvp.Field with key "db.system" and value "mssql"
		//
		// Microsoft SQL Server
		Mssql kvp.Field

		// Mysql is a kvp.Field with key "db.system" and value "mysql"
		//
		// MySQL
		Mysql kvp.Field

		// Oracle is a kvp.Field with key "db.system" and value "oracle"
		//
		// Oracle Database
		Oracle kvp.Field

		// Db2 is a kvp.Field with key "db.system" and value "db2"
		//
		// IBM Db2
		Db2 kvp.Field

		// Postgresql is a kvp.Field with key "db.system" and value "postgresql"
		//
		// PostgreSQL
		Postgresql kvp.Field

		// Redshift is a kvp.Field with key "db.system" and value "redshift"
		//
		// Amazon Redshift
		Redshift kvp.Field

		// Hive is a kvp.Field with key "db.system" and value "hive"
		//
		// Apache Hive
		Hive kvp.Field

		// Cloudscape is a kvp.Field with key "db.system" and value "cloudscape"
		//
		// Cloudscape
		Cloudscape kvp.Field

		// Hsqldb is a kvp.Field with key "db.system" and value "hsqldb"
		//
		// HyperSQL DataBase
		Hsqldb kvp.Field

		// Progress is a kvp.Field with key "db.system" and value "progress"
		//
		// Progress Database
		Progress kvp.Field

		// Maxdb is a kvp.Field with key "db.system" and value "maxdb"
		//
		// SAP MaxDB
		Maxdb kvp.Field

		// Hanadb is a kvp.Field with key "db.system" and value "hanadb"
		//
		// SAP HANA
		Hanadb kvp.Field

		// Ingres is a kvp.Field with key "db.system" and value "ingres"
		//
		// Ingres
		Ingres kvp.Field

		// Firstsql is a kvp.Field with key "db.system" and value "firstsql"
		//
		// FirstSQL
		Firstsql kvp.Field

		// Edb is a kvp.Field with key "db.system" and value "edb"
		//
		// EnterpriseDB
		Edb kvp.Field

		// Cache is a kvp.Field with key "db.system" and value "cache"
		//
		// InterSystems Caché
		Cache kvp.Field

		// Adabas is a kvp.Field with key "db.system" and value "adabas"
		//
		// Adabas (Adaptable Database System)
		Adabas kvp.Field

		// Firebird is a kvp.Field with key "db.system" and value "firebird"
		//
		// Firebird
		Firebird kvp.Field

		// Derby is a kvp.Field with key "db.system" and value "derby"
		//
		// Apache Derby
		Derby kvp.Field

		// Filemaker is a kvp.Field with key "db.system" and value "filemaker"
		//
		// FileMaker
		Filemaker kvp.Field

		// Informix is a kvp.Field with key "db.system" and value "informix"
		//
		// Informix
		Informix kvp.Field

		// Instantdb is a kvp.Field with key "db.system" and value "instantdb"
		//
		// InstantDB
		Instantdb kvp.Field

		// Interbase is a kvp.Field with key "db.system" and value "interbase"
		//
		// InterBase
		Interbase kvp.Field

		// Mariadb is a kvp.Field with key "db.system" and value "mariadb"
		//
		// MariaDB
		Mariadb kvp.Field

		// Netezza is a kvp.Field with key "db.system" and value "netezza"
		//
		// Netezza
		Netezza kvp.Field

		// Pervasive is a kvp.Field with key "db.system" and value "pervasive"
		//
		// Pervasive PSQL
		Pervasive kvp.Field

		// Pointbase is a kvp.Field with key "db.system" and value "pointbase"
		//
		// PointBase
		Pointbase kvp.Field

		// Sqlite is a kvp.Field with key "db.system" and value "sqlite"
		//
		// SQLite
		Sqlite kvp.Field

		// Sybase is a kvp.Field with key "db.system" and value "sybase"
		//
		// Sybase
		Sybase kvp.Field

		// Teradata is a kvp.Field with key "db.system" and value "teradata"
		//
		// Teradata
		Teradata kvp.Field

		// Vertica is a kvp.Field with key "db.system" and value "vertica"
		//
		// Vertica
		Vertica kvp.Field

		// H2 is a kvp.Field with key "db.system" and value "h2"
		//
		// H2
		H2 kvp.Field

		// Coldfusion is a kvp.Field with key "db.system" and value "coldfusion"
		//
		// ColdFusion IMQ
		Coldfusion kvp.Field

		// Cassandra is a kvp.Field with key "db.system" and value "cassandra"
		//
		// Apache Cassandra
		Cassandra kvp.Field

		// Hbase is a kvp.Field with key "db.system" and value "hbase"
		//
		// Apache HBase
		Hbase kvp.Field

		// Mongodb is a kvp.Field with key "db.system" and value "mongodb"
		//
		// MongoDB
		Mongodb kvp.Field

		// Redis is a kvp.Field with key "db.system" and value "redis"
		//
		// Redis
		Redis kvp.Field

		// Couchbase is a kvp.Field with key "db.system" and value "couchbase"
		//
		// Couchbase
		Couchbase kvp.Field

		// Couchdb is a kvp.Field with key "db.system" and value "couchdb"
		//
		// CouchDB
		Couchdb kvp.Field

		// Cosmosdb is a kvp.Field with key "db.system" and value "cosmosdb"
		//
		// Microsoft Azure Cosmos DB
		Cosmosdb kvp.Field

		// Dynamodb is a kvp.Field with key "db.system" and value "dynamodb"
		//
		// Amazon DynamoDB
		Dynamodb kvp.Field

		// Neo4j is a kvp.Field with key "db.system" and value "neo4j"
		//
		// Neo4j
		Neo4j kvp.Field

		// Geode is a kvp.Field with key "db.system" and value "geode"
		//
		// Apache Geode
		Geode kvp.Field

		// Elasticsearch is a kvp.Field with key "db.system" and value "elasticsearch"
		//
		// Elasticsearch
		Elasticsearch kvp.Field

		// Memcached is a kvp.Field with key "db.system" and value "memcached"
		//
		// Memcached
		Memcached kvp.Field

		// Cockroachdb is a kvp.Field with key "db.system" and value "cockroachdb"
		//
		// CockroachDB
		Cockroachdb kvp.Field

		// Opensearch is a kvp.Field with key "db.system" and value "opensearch"
		//
		// OpenSearch
		Opensearch kvp.Field

		// CustomValue returns a kvp.Field with key "db.system" and the value you pass in.
		CustomValue func(value string) kvp.Field
	}

	// ConnectionString returns a kvp.Field with the db.connection_string key and the value you provide.
	//
	// The connection string used to connect to the database. It is recommended to remove embedded
	// credentials.
	//
	// Type: string
	//
	// Examples:
	//   'Server=(localdb)\\v11.0;Integrated Security=true;'
	ConnectionString func(value string) kvp.Field

	// User returns a kvp.Field with the db.user key and the value you provide.
	//
	// Username for accessing the database.
	//
	// Type: string
	//
	// Examples:
	//   'readonly_user', 'reporting_user'
	User func(value string) kvp.Field

	// JcDriverClassname returns a kvp.Field with the db.jdbc.driver_classname key and the value you provide.
	//
	// The fully-qualified class name of the [Java Database Connectivity
	// (JDBC)](https://docs.oracle.com/javase/8/docs/technotes/guides/jdbc/) driver used to connect.
	//
	// Type: string
	//
	// Examples:
	//   'org.postgresql.Driver', 'com.microsoft.sqlserver.jdbc.SQLServerDriver'
	JcDriverClassname func(value string) kvp.Field

	// Name returns a kvp.Field with the db.name key and the value you provide.
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
	Name func(value string) kvp.Field

	// Statement returns a kvp.Field with the db.statement key and the value you provide.
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
	Statement func(value string) kvp.Field

	// Operation returns a kvp.Field with the db.operation key and the value you provide.
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
	Operation func(value string) kvp.Field
}

// This document defines the attributes used to perform database client calls.
var Db = db{
	System: struct {
		OtherSql      kvp.Field
		Mssql         kvp.Field
		Mysql         kvp.Field
		Oracle        kvp.Field
		Db2           kvp.Field
		Postgresql    kvp.Field
		Redshift      kvp.Field
		Hive          kvp.Field
		Cloudscape    kvp.Field
		Hsqldb        kvp.Field
		Progress      kvp.Field
		Maxdb         kvp.Field
		Hanadb        kvp.Field
		Ingres        kvp.Field
		Firstsql      kvp.Field
		Edb           kvp.Field
		Cache         kvp.Field
		Adabas        kvp.Field
		Firebird      kvp.Field
		Derby         kvp.Field
		Filemaker     kvp.Field
		Informix      kvp.Field
		Instantdb     kvp.Field
		Interbase     kvp.Field
		Mariadb       kvp.Field
		Netezza       kvp.Field
		Pervasive     kvp.Field
		Pointbase     kvp.Field
		Sqlite        kvp.Field
		Sybase        kvp.Field
		Teradata      kvp.Field
		Vertica       kvp.Field
		H2            kvp.Field
		Coldfusion    kvp.Field
		Cassandra     kvp.Field
		Hbase         kvp.Field
		Mongodb       kvp.Field
		Redis         kvp.Field
		Couchbase     kvp.Field
		Couchdb       kvp.Field
		Cosmosdb      kvp.Field
		Dynamodb      kvp.Field
		Neo4j         kvp.Field
		Geode         kvp.Field
		Elasticsearch kvp.Field
		Memcached     kvp.Field
		Cockroachdb   kvp.Field
		Opensearch    kvp.Field
		CustomValue   func(value string) kvp.Field
	}{
		OtherSql:      kvp.String("db.system", "other_sql"),
		Mssql:         kvp.String("db.system", "mssql"),
		Mysql:         kvp.String("db.system", "mysql"),
		Oracle:        kvp.String("db.system", "oracle"),
		Db2:           kvp.String("db.system", "db2"),
		Postgresql:    kvp.String("db.system", "postgresql"),
		Redshift:      kvp.String("db.system", "redshift"),
		Hive:          kvp.String("db.system", "hive"),
		Cloudscape:    kvp.String("db.system", "cloudscape"),
		Hsqldb:        kvp.String("db.system", "hsqldb"),
		Progress:      kvp.String("db.system", "progress"),
		Maxdb:         kvp.String("db.system", "maxdb"),
		Hanadb:        kvp.String("db.system", "hanadb"),
		Ingres:        kvp.String("db.system", "ingres"),
		Firstsql:      kvp.String("db.system", "firstsql"),
		Edb:           kvp.String("db.system", "edb"),
		Cache:         kvp.String("db.system", "cache"),
		Adabas:        kvp.String("db.system", "adabas"),
		Firebird:      kvp.String("db.system", "firebird"),
		Derby:         kvp.String("db.system", "derby"),
		Filemaker:     kvp.String("db.system", "filemaker"),
		Informix:      kvp.String("db.system", "informix"),
		Instantdb:     kvp.String("db.system", "instantdb"),
		Interbase:     kvp.String("db.system", "interbase"),
		Mariadb:       kvp.String("db.system", "mariadb"),
		Netezza:       kvp.String("db.system", "netezza"),
		Pervasive:     kvp.String("db.system", "pervasive"),
		Pointbase:     kvp.String("db.system", "pointbase"),
		Sqlite:        kvp.String("db.system", "sqlite"),
		Sybase:        kvp.String("db.system", "sybase"),
		Teradata:      kvp.String("db.system", "teradata"),
		Vertica:       kvp.String("db.system", "vertica"),
		H2:            kvp.String("db.system", "h2"),
		Coldfusion:    kvp.String("db.system", "coldfusion"),
		Cassandra:     kvp.String("db.system", "cassandra"),
		Hbase:         kvp.String("db.system", "hbase"),
		Mongodb:       kvp.String("db.system", "mongodb"),
		Redis:         kvp.String("db.system", "redis"),
		Couchbase:     kvp.String("db.system", "couchbase"),
		Couchdb:       kvp.String("db.system", "couchdb"),
		Cosmosdb:      kvp.String("db.system", "cosmosdb"),
		Dynamodb:      kvp.String("db.system", "dynamodb"),
		Neo4j:         kvp.String("db.system", "neo4j"),
		Geode:         kvp.String("db.system", "geode"),
		Elasticsearch: kvp.String("db.system", "elasticsearch"),
		Memcached:     kvp.String("db.system", "memcached"),
		Cockroachdb:   kvp.String("db.system", "cockroachdb"),
		Opensearch:    kvp.String("db.system", "opensearch"),
		CustomValue: func(value string) kvp.Field {
			return kvp.String("db.system", value)
		},
	},

	ConnectionString: func(value string) kvp.Field {
		return kvp.String("db.connection_string", value)
	},

	User: func(value string) kvp.Field {
		return kvp.String("db.user", value)
	},

	JcDriverClassname: func(value string) kvp.Field {
		return kvp.String("db.jdbc.driver_classname", value)
	},

	Name: func(value string) kvp.Field {
		return kvp.String("db.name", value)
	},

	Statement: func(value string) kvp.Field {
		return kvp.String("db.statement", value)
	},

	Operation: func(value string) kvp.Field {
		return kvp.String("db.operation", value)
	},
}

// Connection-level attributes for Microsoft SQL Server
type dbMssql struct {
	// InstanceName returns a kvp.Field with the db.mssql.instance_name key and the value you provide.
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
	InstanceName func(value string) kvp.Field
}

// Connection-level attributes for Microsoft SQL Server
var DbMssql = dbMssql{
	InstanceName: func(value string) kvp.Field {
		return kvp.String("db.mssql.instance_name", value)
	},
}

// Call-level attributes for Cassandra
type dbCassandra struct {
	// PageSize returns a kvp.Field with the db.cassandra.page_size key and the value you provide.
	//
	// The fetch size used for paging, i.e. how many rows will be returned at once.
	//
	// Type: int
	//
	// Examples:
	//   5000
	PageSize func(value int) kvp.Field

	// ConsistencyLevel struct
	//
	// The consistency level of the query. Based on consistency values from
	// [CQL](https://docs.datastax.com/en/cassandra-oss/3.0/cassandra/dml/dmlConfigConsistency.html).
	//
	// Type: Enum
	ConsistencyLevel struct {
		// All is a kvp.Field with key "db.cassandra.consistency_level" and value "all"
		//
		// all
		All kvp.Field

		// EachQuorum is a kvp.Field with key "db.cassandra.consistency_level" and value "each_quorum"
		//
		// each_quorum
		EachQuorum kvp.Field

		// Quorum is a kvp.Field with key "db.cassandra.consistency_level" and value "quorum"
		//
		// quorum
		Quorum kvp.Field

		// LocalQuorum is a kvp.Field with key "db.cassandra.consistency_level" and value "local_quorum"
		//
		// local_quorum
		LocalQuorum kvp.Field

		// One is a kvp.Field with key "db.cassandra.consistency_level" and value "one"
		//
		// one
		One kvp.Field

		// Two is a kvp.Field with key "db.cassandra.consistency_level" and value "two"
		//
		// two
		Two kvp.Field

		// Three is a kvp.Field with key "db.cassandra.consistency_level" and value "three"
		//
		// three
		Three kvp.Field

		// LocalOne is a kvp.Field with key "db.cassandra.consistency_level" and value "local_one"
		//
		// local_one
		LocalOne kvp.Field

		// Any is a kvp.Field with key "db.cassandra.consistency_level" and value "any"
		//
		// any
		Any kvp.Field

		// Serial is a kvp.Field with key "db.cassandra.consistency_level" and value "serial"
		//
		// serial
		Serial kvp.Field

		// LocalSerial is a kvp.Field with key "db.cassandra.consistency_level" and value "local_serial"
		//
		// local_serial
		LocalSerial kvp.Field
	}

	// Table returns a kvp.Field with the db.cassandra.table key and the value you provide.
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
	Table func(value string) kvp.Field

	// Idempotence returns a kvp.Field with the db.cassandra.idempotence key and the value you provide.
	//
	// Whether or not the query is idempotent.
	//
	// Type: boolean
	Idempotence func(value bool) kvp.Field

	// SpeculativeExecutionCount returns a kvp.Field with the db.cassandra.speculative_execution_count key and the value you provide.
	//
	// The number of times a query was speculatively executed. Not set or `0` if the query was not
	// executed speculatively.
	//
	// Type: int
	//
	// Examples:
	//   0, 2
	SpeculativeExecutionCount func(value int) kvp.Field

	// CoordinatorId returns a kvp.Field with the db.cassandra.coordinator.id key and the value you provide.
	//
	// The ID of the coordinating node for a query.
	//
	// Type: string
	//
	// Examples:
	//   'be13faa2-8574-4d71-926d-27f16cf8a7af'
	CoordinatorId func(value string) kvp.Field

	// CoordinatorDc returns a kvp.Field with the db.cassandra.coordinator.dc key and the value you provide.
	//
	// The data center of the coordinating node for a query.
	//
	// Type: string
	//
	// Examples:
	//   'us-west-2'
	CoordinatorDc func(value string) kvp.Field
}

// Call-level attributes for Cassandra
var DbCassandra = dbCassandra{
	PageSize: func(value int) kvp.Field {
		return kvp.Int("db.cassandra.page_size", value)
	},

	ConsistencyLevel: struct {
		All         kvp.Field
		EachQuorum  kvp.Field
		Quorum      kvp.Field
		LocalQuorum kvp.Field
		One         kvp.Field
		Two         kvp.Field
		Three       kvp.Field
		LocalOne    kvp.Field
		Any         kvp.Field
		Serial      kvp.Field
		LocalSerial kvp.Field
	}{
		All:         kvp.String("db.cassandra.consistency_level", "all"),
		EachQuorum:  kvp.String("db.cassandra.consistency_level", "each_quorum"),
		Quorum:      kvp.String("db.cassandra.consistency_level", "quorum"),
		LocalQuorum: kvp.String("db.cassandra.consistency_level", "local_quorum"),
		One:         kvp.String("db.cassandra.consistency_level", "one"),
		Two:         kvp.String("db.cassandra.consistency_level", "two"),
		Three:       kvp.String("db.cassandra.consistency_level", "three"),
		LocalOne:    kvp.String("db.cassandra.consistency_level", "local_one"),
		Any:         kvp.String("db.cassandra.consistency_level", "any"),
		Serial:      kvp.String("db.cassandra.consistency_level", "serial"),
		LocalSerial: kvp.String("db.cassandra.consistency_level", "local_serial"),
	},

	Table: func(value string) kvp.Field {
		return kvp.String("db.cassandra.table", value)
	},

	Idempotence: func(value bool) kvp.Field {
		return kvp.Bool("db.cassandra.idempotence", value)
	},

	SpeculativeExecutionCount: func(value int) kvp.Field {
		return kvp.Int("db.cassandra.speculative_execution_count", value)
	},

	CoordinatorId: func(value string) kvp.Field {
		return kvp.String("db.cassandra.coordinator.id", value)
	},

	CoordinatorDc: func(value string) kvp.Field {
		return kvp.String("db.cassandra.coordinator.dc", value)
	},
}

// Call-level attributes for Redis
type dbRedis struct {
	// DatabaseIndex returns a kvp.Field with the db.redis.database_index key and the value you provide.
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
	DatabaseIndex func(value int) kvp.Field
}

// Call-level attributes for Redis
var DbRedis = dbRedis{
	DatabaseIndex: func(value int) kvp.Field {
		return kvp.Int("db.redis.database_index", value)
	},
}

// Call-level attributes for MongoDB
type dbMongodb struct {
	// Collection returns a kvp.Field with the db.mongodb.collection key and the value you provide.
	//
	// The collection being accessed within the database stated in `db.name`.
	//
	// Type: string
	//
	// Requirement Level: Required
	//
	// Examples:
	//   'customers', 'products'
	Collection func(value string) kvp.Field
}

// Call-level attributes for MongoDB
var DbMongodb = dbMongodb{
	Collection: func(value string) kvp.Field {
		return kvp.String("db.mongodb.collection", value)
	},
}

// Call-level attributes for SQL databases
type dbSql struct {
	// Table returns a kvp.Field with the db.sql.table key and the value you provide.
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
	Table func(value string) kvp.Field
}

// Call-level attributes for SQL databases
var DbSql = dbSql{
	Table: func(value string) kvp.Field {
		return kvp.String("db.sql.table", value)
	},
}

// Semantic convention group for specific technologies
type dbTech struct {
}

// Semantic convention group for specific technologies
var DbTech = dbTech{}

// This document defines the attributes used to report a single exception associated with a span.
type exception struct {
	// Type returns a kvp.Field with the exception.type key and the value you provide.
	//
	// The type of the exception (its fully-qualified class name, if applicable). The dynamic type of
	// the exception should be preferred over the static type in languages that support it.
	//
	// Type: string
	//
	// Examples:
	//   'java.net.ConnectException', 'OSError'
	Type func(value string) kvp.Field

	// Message returns a kvp.Field with the exception.message key and the value you provide.
	//
	// The exception message.
	//
	// Type: string
	//
	// Examples:
	//   'Division by zero', "Can't convert 'int' object to str implicitly"
	Message func(value string) kvp.Field

	// Stacktrace returns a kvp.Field with the exception.stacktrace key and the value you provide.
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
	Stacktrace func(value string) kvp.Field

	// Escaped returns a kvp.Field with the exception.escaped key and the value you provide.
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
	Escaped func(value bool) kvp.Field
}

// This document defines the attributes used to report a single exception associated with a span.
var Exception = exception{
	Type: func(value string) kvp.Field {
		return kvp.String("exception.type", value)
	},

	Message: func(value string) kvp.Field {
		return kvp.String("exception.message", value)
	},

	Stacktrace: func(value string) kvp.Field {
		return kvp.String("exception.stacktrace", value)
	},

	Escaped: func(value bool) kvp.Field {
		return kvp.Bool("exception.escaped", value)
	},
}

// This semantic convention describes an instance of a function that runs without provisioning or
// managing of servers (also known as serverless functions or Function as a Service (FaaS)) with
// spans.
type faasSpan struct {

	// Trigger struct
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
	Trigger struct {
		// Datasource is a kvp.Field with key "faas.trigger" and value "datasource"
		//
		// A response to some data source operation such as a database or filesystem read/write
		Datasource kvp.Field

		// Http is a kvp.Field with key "faas.trigger" and value "http"
		//
		// To provide an answer to an inbound HTTP request
		Http kvp.Field

		// Pubsub is a kvp.Field with key "faas.trigger" and value "pubsub"
		//
		// A function is set to be executed when messages are sent to a messaging system
		Pubsub kvp.Field

		// Timer is a kvp.Field with key "faas.trigger" and value "timer"
		//
		// A function is scheduled to be executed regularly
		Timer kvp.Field

		// Other is a kvp.Field with key "faas.trigger" and value "other"
		//
		// If none of the others apply
		Other kvp.Field
	}

	// Execution returns a kvp.Field with the faas.execution key and the value you provide.
	//
	// The execution ID of the current function execution.
	//
	// Type: string
	//
	// Examples:
	//   'af9d5aa4-a685-4c5f-a22b-444f80b3cc28'
	Execution func(value string) kvp.Field
}

// This semantic convention describes an instance of a function that runs without provisioning or
// managing of servers (also known as serverless functions or Function as a Service (FaaS)) with
// spans.
var FaasSpan = faasSpan{
	Trigger: struct {
		Datasource kvp.Field
		Http       kvp.Field
		Pubsub     kvp.Field
		Timer      kvp.Field
		Other      kvp.Field
	}{
		Datasource: kvp.String("faas.trigger", "datasource"),
		Http:       kvp.String("faas.trigger", "http"),
		Pubsub:     kvp.String("faas.trigger", "pubsub"),
		Timer:      kvp.String("faas.trigger", "timer"),
		Other:      kvp.String("faas.trigger", "other"),
	},

	Execution: func(value string) kvp.Field {
		return kvp.String("faas.execution", value)
	},
}

// Semantic Convention for FaaS triggered as a response to some data source operation such as a
// database or filesystem read/write.
type faasSpanDatasource struct {
	// Collection returns a kvp.Field with the faas.document.collection key and the value you provide.
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
	Collection func(value string) kvp.Field

	// Operation struct
	//
	// Describes the type of the operation that was performed on the data.
	//
	// Type: Enum
	//
	// Requirement Level: Required
	Operation struct {
		// Insert is a kvp.Field with key "faas.document.operation" and value "insert"
		//
		// When a new object is created
		Insert kvp.Field

		// Edit is a kvp.Field with key "faas.document.operation" and value "edit"
		//
		// When an object is modified
		Edit kvp.Field

		// Delete is a kvp.Field with key "faas.document.operation" and value "delete"
		//
		// When an object is deleted
		Delete kvp.Field

		// CustomValue returns a kvp.Field with key "faas.document.operation" and the value you pass in.
		CustomValue func(value string) kvp.Field
	}

	// Time returns a kvp.Field with the faas.document.time key and the value you provide.
	//
	// A string containing the time when the data was accessed in the [ISO
	// 8601](https://www.iso.org/iso-8601-date-and-time-format.html) format expressed in
	// [UTC](https://www.w3.org/TR/NOTE-datetime).
	//
	// Type: string
	//
	// Examples:
	//   '2020-01-23T13:47:06Z'
	Time func(value string) kvp.Field

	// Name returns a kvp.Field with the faas.document.name key and the value you provide.
	//
	// The document name/table subjected to the operation. For example, in Cloud Storage or S3 is the
	// name of the file, and in Cosmos DB the table name.
	//
	// Type: string
	//
	// Examples:
	//   'myFile.txt', 'myTableName'
	Name func(value string) kvp.Field
}

// Semantic Convention for FaaS triggered as a response to some data source operation such as a
// database or filesystem read/write.
var FaasSpanDatasource = faasSpanDatasource{
	Collection: func(value string) kvp.Field {
		return kvp.String("faas.document.collection", value)
	},

	Operation: struct {
		Insert      kvp.Field
		Edit        kvp.Field
		Delete      kvp.Field
		CustomValue func(value string) kvp.Field
	}{
		Insert: kvp.String("faas.document.operation", "insert"),
		Edit:   kvp.String("faas.document.operation", "edit"),
		Delete: kvp.String("faas.document.operation", "delete"),
		CustomValue: func(value string) kvp.Field {
			return kvp.String("faas.document.operation", value)
		},
	},

	Time: func(value string) kvp.Field {
		return kvp.String("faas.document.time", value)
	},

	Name: func(value string) kvp.Field {
		return kvp.String("faas.document.name", value)
	},
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
	// Time returns a kvp.Field with the faas.time key and the value you provide.
	//
	// A string containing the function invocation time in the [ISO
	// 8601](https://www.iso.org/iso-8601-date-and-time-format.html) format expressed in
	// [UTC](https://www.w3.org/TR/NOTE-datetime).
	//
	// Type: string
	//
	// Examples:
	//   '2020-01-23T13:47:06Z'
	Time func(value string) kvp.Field

	// Cron returns a kvp.Field with the faas.cron key and the value you provide.
	//
	// A string containing the schedule period as [Cron
	// Expression](https://docs.oracle.com/cd/E12058_01/doc/doc.1014/e12030/cron_expressions.htm).
	//
	// Type: string
	//
	// Examples:
	//   '0/5 * * * ? *'
	Cron func(value string) kvp.Field
}

// Semantic Convention for FaaS scheduled to be executed regularly.
var FaasSpanTimer = faasSpanTimer{
	Time: func(value string) kvp.Field {
		return kvp.String("faas.time", value)
	},

	Cron: func(value string) kvp.Field {
		return kvp.String("faas.cron", value)
	},
}

// Contains additional attributes for incoming FaaS spans.
type faasSpanIn struct {
	// Coldstart returns a kvp.Field with the faas.coldstart key and the value you provide.
	//
	// A boolean that is true if the serverless function is executed for the first time (aka cold-
	// start).
	//
	// Type: boolean
	Coldstart func(value bool) kvp.Field
}

// Contains additional attributes for incoming FaaS spans.
var FaasSpanIn = faasSpanIn{
	Coldstart: func(value bool) kvp.Field {
		return kvp.Bool("faas.coldstart", value)
	},
}

// Contains additional attributes for outgoing FaaS spans.
type faasSpanOut struct {
	// InvokedName returns a kvp.Field with the faas.invoked_name key and the value you provide.
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
	InvokedName func(value string) kvp.Field

	// InvokedProvider struct
	//
	// The cloud provider of the invoked function.
	//
	// Type: Enum
	//
	// Requirement Level: Required
	//
	// Note:
	// SHOULD be equal to the `cloud.provider` resource attribute of the invoked function.
	InvokedProvider struct {
		// AlibabaCloud is a kvp.Field with key "faas.invoked_provider" and value "alibaba_cloud"
		//
		// Alibaba Cloud
		AlibabaCloud kvp.Field

		// Aws is a kvp.Field with key "faas.invoked_provider" and value "aws"
		//
		// Amazon Web Services
		Aws kvp.Field

		// Azure is a kvp.Field with key "faas.invoked_provider" and value "azure"
		//
		// Microsoft Azure
		Azure kvp.Field

		// Gcp is a kvp.Field with key "faas.invoked_provider" and value "gcp"
		//
		// Google Cloud Platform
		Gcp kvp.Field

		// TencentCloud is a kvp.Field with key "faas.invoked_provider" and value "tencent_cloud"
		//
		// Tencent Cloud
		TencentCloud kvp.Field

		// CustomValue returns a kvp.Field with key "faas.invoked_provider" and the value you pass in.
		CustomValue func(value string) kvp.Field
	}

	// InvokedRegion returns a kvp.Field with the faas.invoked_region key and the value you provide.
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
	InvokedRegion func(value string) kvp.Field
}

// Contains additional attributes for outgoing FaaS spans.
var FaasSpanOut = faasSpanOut{
	InvokedName: func(value string) kvp.Field {
		return kvp.String("faas.invoked_name", value)
	},

	InvokedProvider: struct {
		AlibabaCloud kvp.Field
		Aws          kvp.Field
		Azure        kvp.Field
		Gcp          kvp.Field
		TencentCloud kvp.Field
		CustomValue  func(value string) kvp.Field
	}{
		AlibabaCloud: kvp.String("faas.invoked_provider", "alibaba_cloud"),
		Aws:          kvp.String("faas.invoked_provider", "aws"),
		Azure:        kvp.String("faas.invoked_provider", "azure"),
		Gcp:          kvp.String("faas.invoked_provider", "gcp"),
		TencentCloud: kvp.String("faas.invoked_provider", "tencent_cloud"),
		CustomValue: func(value string) kvp.Field {
			return kvp.String("faas.invoked_provider", value)
		},
	},

	InvokedRegion: func(value string) kvp.Field {
		return kvp.String("faas.invoked_region", value)
	},
}

// These attributes may be used for any network related operation.
type network struct {

	// Transport struct
	//
	// Transport protocol used. See note below.
	//
	// Type: Enum
	Transport struct {
		// IpTcp is a kvp.Field with key "net.transport" and value "ip_tcp"
		//
		// ip_tcp
		IpTcp kvp.Field

		// IpUdp is a kvp.Field with key "net.transport" and value "ip_udp"
		//
		// ip_udp
		IpUdp kvp.Field

		// Pipe is a kvp.Field with key "net.transport" and value "pipe"
		//
		// Named or anonymous pipe. See note below
		Pipe kvp.Field

		// Inproc is a kvp.Field with key "net.transport" and value "inproc"
		//
		// In-process communication
		Inproc kvp.Field

		// Other is a kvp.Field with key "net.transport" and value "other"
		//
		// Something else (non IP-based)
		Other kvp.Field

		// CustomValue returns a kvp.Field with key "net.transport" and the value you pass in.
		CustomValue func(value string) kvp.Field
	}

	// AppProtocolName returns a kvp.Field with the net.app.protocol.name key and the value you provide.
	//
	// Application layer protocol used. The value SHOULD be normalized to lowercase.
	//
	// Type: string
	//
	// Examples:
	//   'amqp', 'http', 'mqtt'
	AppProtocolName func(value string) kvp.Field

	// AppProtocolVersion returns a kvp.Field with the net.app.protocol.version key and the value you provide.
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
	AppProtocolVersion func(value string) kvp.Field

	// SockPeerName returns a kvp.Field with the net.sock.peer.name key and the value you provide.
	//
	// Remote socket peer name.
	//
	// Type: string
	//
	// Requirement Level: Recommended
	//
	// Examples:
	//   'proxy.example.com'
	SockPeerName func(value string) kvp.Field

	// SockPeerAddr returns a kvp.Field with the net.sock.peer.addr key and the value you provide.
	//
	// Remote socket peer address: IPv4 or IPv6 for internet protocols, path for local communication,
	// [etc](https://man7.org/linux/man-pages/man7/address_families.7.html).
	//
	// Type: string
	//
	// Examples:
	//   '127.0.0.1', '/tmp/mysql.sock'
	SockPeerAddr func(value string) kvp.Field

	// SockPeerPort returns a kvp.Field with the net.sock.peer.port key and the value you provide.
	//
	// Remote socket peer port.
	//
	// Type: int
	//
	// Requirement Level: Recommended
	//
	// Examples:
	//   16456
	SockPeerPort func(value int) kvp.Field

	// SockFamily struct
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
	SockFamily struct {
		// Inet is a kvp.Field with key "net.sock.family" and value "inet"
		//
		// IPv4 address
		Inet kvp.Field

		// Inet6 is a kvp.Field with key "net.sock.family" and value "inet6"
		//
		// IPv6 address
		Inet6 kvp.Field

		// Unix is a kvp.Field with key "net.sock.family" and value "unix"
		//
		// Unix domain socket path
		Unix kvp.Field

		// CustomValue returns a kvp.Field with key "net.sock.family" and the value you pass in.
		CustomValue func(value string) kvp.Field
	}

	// PeerName returns a kvp.Field with the net.peer.name key and the value you provide.
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
	PeerName func(value string) kvp.Field

	// PeerPort returns a kvp.Field with the net.peer.port key and the value you provide.
	//
	// Logical remote port number
	//
	// Type: int
	//
	// Examples:
	//   80, 8080, 443
	PeerPort func(value int) kvp.Field

	// HostName returns a kvp.Field with the net.host.name key and the value you provide.
	//
	// Logical local hostname or similar, see note below.
	//
	// Type: string
	//
	// Examples:
	//   'localhost'
	HostName func(value string) kvp.Field

	// HostPort returns a kvp.Field with the net.host.port key and the value you provide.
	//
	// Logical local port number, preferably the one that the peer used to connect
	//
	// Type: int
	//
	// Examples:
	//   8080
	HostPort func(value int) kvp.Field

	// SockHostAddr returns a kvp.Field with the net.sock.host.addr key and the value you provide.
	//
	// Local socket address. Useful in case of a multi-IP host.
	//
	// Type: string
	//
	// Examples:
	//   '192.168.0.1'
	SockHostAddr func(value string) kvp.Field

	// SockHostPort returns a kvp.Field with the net.sock.host.port key and the value you provide.
	//
	// Local socket port number.
	//
	// Type: int
	//
	// Requirement Level: Recommended
	//
	// Examples:
	//   35555
	SockHostPort func(value int) kvp.Field

	// HostConnectionType struct
	//
	// The internet connection type currently being used by the host.
	//
	// Type: Enum
	//
	// Examples:
	//   'wifi'
	HostConnectionType struct {
		// Wifi is a kvp.Field with key "net.host.connection.type" and value "wifi"
		//
		// wifi
		Wifi kvp.Field

		// Wired is a kvp.Field with key "net.host.connection.type" and value "wired"
		//
		// wired
		Wired kvp.Field

		// Cell is a kvp.Field with key "net.host.connection.type" and value "cell"
		//
		// cell
		Cell kvp.Field

		// Unavailable is a kvp.Field with key "net.host.connection.type" and value "unavailable"
		//
		// unavailable
		Unavailable kvp.Field

		// Unknown is a kvp.Field with key "net.host.connection.type" and value "unknown"
		//
		// unknown
		Unknown kvp.Field

		// CustomValue returns a kvp.Field with key "net.host.connection.type" and the value you pass in.
		CustomValue func(value string) kvp.Field
	}

	// HostConnectionSubtype struct
	//
	// This describes more details regarding the connection.type. It may be the type of cell technology
	// connection, but it could be used for describing details about a wifi connection.
	//
	// Type: Enum
	//
	// Examples:
	//   'LTE'
	HostConnectionSubtype struct {
		// Gprs is a kvp.Field with key "net.host.connection.subtype" and value "gprs"
		//
		// GPRS
		Gprs kvp.Field

		// Edge is a kvp.Field with key "net.host.connection.subtype" and value "edge"
		//
		// EDGE
		Edge kvp.Field

		// Umts is a kvp.Field with key "net.host.connection.subtype" and value "umts"
		//
		// UMTS
		Umts kvp.Field

		// Cdma is a kvp.Field with key "net.host.connection.subtype" and value "cdma"
		//
		// CDMA
		Cdma kvp.Field

		// Evdo0 is a kvp.Field with key "net.host.connection.subtype" and value "evdo_0"
		//
		// EVDO Rel. 0
		Evdo0 kvp.Field

		// EvdoA is a kvp.Field with key "net.host.connection.subtype" and value "evdo_a"
		//
		// EVDO Rev. A
		EvdoA kvp.Field

		// Cdma20001xrtt is a kvp.Field with key "net.host.connection.subtype" and value "cdma2000_1xrtt"
		//
		// CDMA2000 1XRTT
		Cdma20001xrtt kvp.Field

		// Hsdpa is a kvp.Field with key "net.host.connection.subtype" and value "hsdpa"
		//
		// HSDPA
		Hsdpa kvp.Field

		// Hsupa is a kvp.Field with key "net.host.connection.subtype" and value "hsupa"
		//
		// HSUPA
		Hsupa kvp.Field

		// Hspa is a kvp.Field with key "net.host.connection.subtype" and value "hspa"
		//
		// HSPA
		Hspa kvp.Field

		// Iden is a kvp.Field with key "net.host.connection.subtype" and value "iden"
		//
		// IDEN
		Iden kvp.Field

		// EvdoB is a kvp.Field with key "net.host.connection.subtype" and value "evdo_b"
		//
		// EVDO Rev. B
		EvdoB kvp.Field

		// Lte is a kvp.Field with key "net.host.connection.subtype" and value "lte"
		//
		// LTE
		Lte kvp.Field

		// Ehrpd is a kvp.Field with key "net.host.connection.subtype" and value "ehrpd"
		//
		// EHRPD
		Ehrpd kvp.Field

		// Hspap is a kvp.Field with key "net.host.connection.subtype" and value "hspap"
		//
		// HSPAP
		Hspap kvp.Field

		// Gsm is a kvp.Field with key "net.host.connection.subtype" and value "gsm"
		//
		// GSM
		Gsm kvp.Field

		// TdScdma is a kvp.Field with key "net.host.connection.subtype" and value "td_scdma"
		//
		// TD-SCDMA
		TdScdma kvp.Field

		// Iwlan is a kvp.Field with key "net.host.connection.subtype" and value "iwlan"
		//
		// IWLAN
		Iwlan kvp.Field

		// Nr is a kvp.Field with key "net.host.connection.subtype" and value "nr"
		//
		// 5G NR (New Radio)
		Nr kvp.Field

		// Nrnsa is a kvp.Field with key "net.host.connection.subtype" and value "nrnsa"
		//
		// 5G NRNSA (New Radio Non-Standalone)
		Nrnsa kvp.Field

		// LteCa is a kvp.Field with key "net.host.connection.subtype" and value "lte_ca"
		//
		// LTE CA
		LteCa kvp.Field

		// CustomValue returns a kvp.Field with key "net.host.connection.subtype" and the value you pass in.
		CustomValue func(value string) kvp.Field
	}

	// HostCarrierName returns a kvp.Field with the net.host.carrier.name key and the value you provide.
	//
	// The name of the mobile carrier.
	//
	// Type: string
	//
	// Examples:
	//   'sprint'
	HostCarrierName func(value string) kvp.Field

	// HostCarrierMcc returns a kvp.Field with the net.host.carrier.mcc key and the value you provide.
	//
	// The mobile carrier country code.
	//
	// Type: string
	//
	// Examples:
	//   '310'
	HostCarrierMcc func(value string) kvp.Field

	// HostCarrierMnc returns a kvp.Field with the net.host.carrier.mnc key and the value you provide.
	//
	// The mobile carrier network code.
	//
	// Type: string
	//
	// Examples:
	//   '001'
	HostCarrierMnc func(value string) kvp.Field

	// HostCarrierIcc returns a kvp.Field with the net.host.carrier.icc key and the value you provide.
	//
	// The ISO 3166-1 alpha-2 2-character country code associated with the mobile carrier network.
	//
	// Type: string
	//
	// Examples:
	//   'DE'
	HostCarrierIcc func(value string) kvp.Field
}

// These attributes may be used for any network related operation.
var Network = network{
	Transport: struct {
		IpTcp       kvp.Field
		IpUdp       kvp.Field
		Pipe        kvp.Field
		Inproc      kvp.Field
		Other       kvp.Field
		CustomValue func(value string) kvp.Field
	}{
		IpTcp:  kvp.String("net.transport", "ip_tcp"),
		IpUdp:  kvp.String("net.transport", "ip_udp"),
		Pipe:   kvp.String("net.transport", "pipe"),
		Inproc: kvp.String("net.transport", "inproc"),
		Other:  kvp.String("net.transport", "other"),
		CustomValue: func(value string) kvp.Field {
			return kvp.String("net.transport", value)
		},
	},

	AppProtocolName: func(value string) kvp.Field {
		return kvp.String("net.app.protocol.name", value)
	},

	AppProtocolVersion: func(value string) kvp.Field {
		return kvp.String("net.app.protocol.version", value)
	},

	SockPeerName: func(value string) kvp.Field {
		return kvp.String("net.sock.peer.name", value)
	},

	SockPeerAddr: func(value string) kvp.Field {
		return kvp.String("net.sock.peer.addr", value)
	},

	SockPeerPort: func(value int) kvp.Field {
		return kvp.Int("net.sock.peer.port", value)
	},

	SockFamily: struct {
		Inet        kvp.Field
		Inet6       kvp.Field
		Unix        kvp.Field
		CustomValue func(value string) kvp.Field
	}{
		Inet:  kvp.String("net.sock.family", "inet"),
		Inet6: kvp.String("net.sock.family", "inet6"),
		Unix:  kvp.String("net.sock.family", "unix"),
		CustomValue: func(value string) kvp.Field {
			return kvp.String("net.sock.family", value)
		},
	},

	PeerName: func(value string) kvp.Field {
		return kvp.String("net.peer.name", value)
	},

	PeerPort: func(value int) kvp.Field {
		return kvp.Int("net.peer.port", value)
	},

	HostName: func(value string) kvp.Field {
		return kvp.String("net.host.name", value)
	},

	HostPort: func(value int) kvp.Field {
		return kvp.Int("net.host.port", value)
	},

	SockHostAddr: func(value string) kvp.Field {
		return kvp.String("net.sock.host.addr", value)
	},

	SockHostPort: func(value int) kvp.Field {
		return kvp.Int("net.sock.host.port", value)
	},

	HostConnectionType: struct {
		Wifi        kvp.Field
		Wired       kvp.Field
		Cell        kvp.Field
		Unavailable kvp.Field
		Unknown     kvp.Field
		CustomValue func(value string) kvp.Field
	}{
		Wifi:        kvp.String("net.host.connection.type", "wifi"),
		Wired:       kvp.String("net.host.connection.type", "wired"),
		Cell:        kvp.String("net.host.connection.type", "cell"),
		Unavailable: kvp.String("net.host.connection.type", "unavailable"),
		Unknown:     kvp.String("net.host.connection.type", "unknown"),
		CustomValue: func(value string) kvp.Field {
			return kvp.String("net.host.connection.type", value)
		},
	},

	HostConnectionSubtype: struct {
		Gprs          kvp.Field
		Edge          kvp.Field
		Umts          kvp.Field
		Cdma          kvp.Field
		Evdo0         kvp.Field
		EvdoA         kvp.Field
		Cdma20001xrtt kvp.Field
		Hsdpa         kvp.Field
		Hsupa         kvp.Field
		Hspa          kvp.Field
		Iden          kvp.Field
		EvdoB         kvp.Field
		Lte           kvp.Field
		Ehrpd         kvp.Field
		Hspap         kvp.Field
		Gsm           kvp.Field
		TdScdma       kvp.Field
		Iwlan         kvp.Field
		Nr            kvp.Field
		Nrnsa         kvp.Field
		LteCa         kvp.Field
		CustomValue   func(value string) kvp.Field
	}{
		Gprs:          kvp.String("net.host.connection.subtype", "gprs"),
		Edge:          kvp.String("net.host.connection.subtype", "edge"),
		Umts:          kvp.String("net.host.connection.subtype", "umts"),
		Cdma:          kvp.String("net.host.connection.subtype", "cdma"),
		Evdo0:         kvp.String("net.host.connection.subtype", "evdo_0"),
		EvdoA:         kvp.String("net.host.connection.subtype", "evdo_a"),
		Cdma20001xrtt: kvp.String("net.host.connection.subtype", "cdma2000_1xrtt"),
		Hsdpa:         kvp.String("net.host.connection.subtype", "hsdpa"),
		Hsupa:         kvp.String("net.host.connection.subtype", "hsupa"),
		Hspa:          kvp.String("net.host.connection.subtype", "hspa"),
		Iden:          kvp.String("net.host.connection.subtype", "iden"),
		EvdoB:         kvp.String("net.host.connection.subtype", "evdo_b"),
		Lte:           kvp.String("net.host.connection.subtype", "lte"),
		Ehrpd:         kvp.String("net.host.connection.subtype", "ehrpd"),
		Hspap:         kvp.String("net.host.connection.subtype", "hspap"),
		Gsm:           kvp.String("net.host.connection.subtype", "gsm"),
		TdScdma:       kvp.String("net.host.connection.subtype", "td_scdma"),
		Iwlan:         kvp.String("net.host.connection.subtype", "iwlan"),
		Nr:            kvp.String("net.host.connection.subtype", "nr"),
		Nrnsa:         kvp.String("net.host.connection.subtype", "nrnsa"),
		LteCa:         kvp.String("net.host.connection.subtype", "lte_ca"),
		CustomValue: func(value string) kvp.Field {
			return kvp.String("net.host.connection.subtype", value)
		},
	},

	HostCarrierName: func(value string) kvp.Field {
		return kvp.String("net.host.carrier.name", value)
	},

	HostCarrierMcc: func(value string) kvp.Field {
		return kvp.String("net.host.carrier.mcc", value)
	},

	HostCarrierMnc: func(value string) kvp.Field {
		return kvp.String("net.host.carrier.mnc", value)
	},

	HostCarrierIcc: func(value string) kvp.Field {
		return kvp.String("net.host.carrier.icc", value)
	},
}

// Operations that access some remote service.
type peer struct {
	// Service returns a kvp.Field with the peer.service key and the value you provide.
	//
	// The [`service.name`](../../resource/semantic_conventions/README.md#service) of the remote
	// service. SHOULD be equal to the actual `service.name` resource attribute of the remote service if
	// any.
	//
	// Type: string
	//
	// Examples:
	//   'AuthTokenCache'
	Service func(value string) kvp.Field
}

// Operations that access some remote service.
var Peer = peer{
	Service: func(value string) kvp.Field {
		return kvp.String("peer.service", value)
	},
}

// These attributes may be used for any operation with an authenticated and/or authorized enduser.
type identity struct {
	// Id returns a kvp.Field with the enduser.id key and the value you provide.
	//
	// Username or client_id extracted from the access token or
	// [Authorization](https://tools.ietf.org/html/rfc7235#section-4.2) header in the inbound request
	// from outside the system.
	//
	// Type: string
	//
	// Examples:
	//   'username'
	Id func(value string) kvp.Field

	// Role returns a kvp.Field with the enduser.role key and the value you provide.
	//
	// Actual/assumed role the client is making the request under extracted from token or application
	// security context.
	//
	// Type: string
	//
	// Examples:
	//   'admin'
	Role func(value string) kvp.Field

	// Scope returns a kvp.Field with the enduser.scope key and the value you provide.
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
	Scope func(value string) kvp.Field
}

// These attributes may be used for any operation with an authenticated and/or authorized enduser.
var Identity = identity{
	Id: func(value string) kvp.Field {
		return kvp.String("enduser.id", value)
	},

	Role: func(value string) kvp.Field {
		return kvp.String("enduser.role", value)
	},

	Scope: func(value string) kvp.Field {
		return kvp.String("enduser.scope", value)
	},
}

// These attributes may be used for any operation to store information about a thread that started a
// span.
type thread struct {
	// Id returns a kvp.Field with the thread.id key and the value you provide.
	//
	// Current "managed" thread ID (as opposed to OS thread ID).
	//
	// Type: int
	//
	// Examples:
	//   42
	Id func(value int) kvp.Field

	// Name returns a kvp.Field with the thread.name key and the value you provide.
	//
	// Current thread name.
	//
	// Type: string
	//
	// Examples:
	//   'main'
	Name func(value string) kvp.Field
}

// These attributes may be used for any operation to store information about a thread that started a
// span.
var Thread = thread{
	Id: func(value int) kvp.Field {
		return kvp.Int("thread.id", value)
	},

	Name: func(value string) kvp.Field {
		return kvp.String("thread.name", value)
	},
}

// These attributes allow to report this unit of code and therefore to provide more context about
// the span.
type code struct {
	// Function returns a kvp.Field with the code.function key and the value you provide.
	//
	// The method or function name, or equivalent (usually rightmost part of the code unit's name).
	//
	// Type: string
	//
	// Examples:
	//   'serveRequest'
	Function func(value string) kvp.Field

	// Namespace returns a kvp.Field with the code.namespace key and the value you provide.
	//
	// The "namespace" within which `code.function` is defined. Usually the qualified class or module
	// name, such that `code.namespace` + some separator + `code.function` form a unique identifier for
	// the code unit.
	//
	// Type: string
	//
	// Examples:
	//   'com.example.MyHttpService'
	Namespace func(value string) kvp.Field

	// Filepath returns a kvp.Field with the code.filepath key and the value you provide.
	//
	// The source code file name that identifies the code unit as uniquely as possible (preferably an
	// absolute file path).
	//
	// Type: string
	//
	// Examples:
	//   '/usr/local/MyApplication/content_root/app/index.php'
	Filepath func(value string) kvp.Field

	// Lineno returns a kvp.Field with the code.lineno key and the value you provide.
	//
	// The line number in `code.filepath` best representing the operation. It SHOULD point within the
	// code unit named in `code.function`.
	//
	// Type: int
	//
	// Examples:
	//   42
	Lineno func(value int) kvp.Field
}

// These attributes allow to report this unit of code and therefore to provide more context about
// the span.
var Code = code{
	Function: func(value string) kvp.Field {
		return kvp.String("code.function", value)
	},

	Namespace: func(value string) kvp.Field {
		return kvp.String("code.namespace", value)
	},

	Filepath: func(value string) kvp.Field {
		return kvp.String("code.filepath", value)
	},

	Lineno: func(value int) kvp.Field {
		return kvp.Int("code.lineno", value)
	},
}

// This document specifies common metadata specific to Git resources in user repositories.
type ghGit struct {
	// Ref returns a kvp.Field with the gh.git.ref key and the value you provide.
	//
	// A Git ref.
	//
	// Type: string
	//
	// Examples:
	//   'refs/heads/main', 'refs/tags/v1.0'
	Ref func(value string) kvp.Field

	// Commit returns a kvp.Field with the gh.git.commit key and the value you provide.
	//
	// A Git commit, in the form of the hex encoding of the commit checksum.
	//
	// Type: string
	//
	// Examples:
	//   'e039abca90f1a9c965f28822094fffa5256e9d58'
	Commit func(value string) kvp.Field

	// ShortCommit returns a kvp.Field with the gh.git.short_commit key and the value you provide.
	//
	// Like `commit`, but in short form.
	//
	// Type: string
	//
	// Examples:
	//   '1d1b1f3'
	ShortCommit func(value string) kvp.Field

	// Path returns a kvp.Field with the gh.git.path key and the value you provide.
	//
	// Path to a file in a Git repository
	//
	// Type: string
	//
	// Examples:
	//   '.github/runtime.yml'
	Path func(value string) kvp.Field
}

// This document specifies common metadata specific to Git resources in user repositories.
var GhGit = ghGit{
	Ref: func(value string) kvp.Field {
		return kvp.String("gh.git.ref", value)
	},

	Commit: func(value string) kvp.Field {
		return kvp.String("gh.git.commit", value)
	},

	ShortCommit: func(value string) kvp.Field {
		return kvp.String("gh.git.short_commit", value)
	},

	Path: func(value string) kvp.Field {
		return kvp.String("gh.git.path", value)
	},
}

// These attributes allow to report this unit of code and therefore to provide more context about
// where a span ended.
type ghCodeEnd struct {
	// Function returns a kvp.Field with the gh.code.end.function key and the value you provide.
	//
	// The method or function name, or equivalent (usually rightmost part of the code unit's name).
	//
	// Type: string
	//
	// Examples:
	//   'serveRequest'
	Function func(value string) kvp.Field

	// Namespace returns a kvp.Field with the gh.code.end.namespace key and the value you provide.
	//
	// The "namespace" within which `gh.code.end.function` is defined. Usually the qualified class or
	// module name, such that `gh.code.end.namespace` + some separator + the type name (if available)
	// form a unique identifier for the code unit.
	//
	// Type: string
	//
	// Examples:
	//   'com.example.MyHttpService'
	Namespace func(value string) kvp.Field

	// Filepath returns a kvp.Field with the gh.code.end.filepath key and the value you provide.
	//
	// The source code file name that identifies the code unit as uniquely as possible (preferably an
	// absolute file path).
	//
	// Type: string
	//
	// Examples:
	//   '/usr/local/MyApplication/content_root/app/index.php'
	Filepath func(value string) kvp.Field

	// Lineno returns a kvp.Field with the gh.code.end.lineno key and the value you provide.
	//
	// The line number in `gh.code.end.filepath` best representing the operation. It SHOULD point within
	// the code unit named in `gh.code.end.function`.
	//
	// Type: int
	//
	// Examples:
	//   42
	Lineno func(value int) kvp.Field
}

// These attributes allow to report this unit of code and therefore to provide more context about
// where a span ended.
var GhCodeEnd = ghCodeEnd{
	Function: func(value string) kvp.Field {
		return kvp.String("gh.code.end.function", value)
	},

	Namespace: func(value string) kvp.Field {
		return kvp.String("gh.code.end.namespace", value)
	},

	Filepath: func(value string) kvp.Field {
		return kvp.String("gh.code.end.filepath", value)
	},

	Lineno: func(value int) kvp.Field {
		return kvp.Int("gh.code.end.lineno", value)
	},
}

// This document specifies common exception metadata specific the copilot-telemetry-service
type ghCopilotTelemetry struct {
	// AppEnvironment returns a kvp.Field with the gh.copilot_telemetry.app_environment key and the value you provide.
	//
	// The value of the APP_ENV environment variable, which is apparently not the deployment environment
	// even though it has the same values.
	//
	// Type: string
	//
	// Examples:
	//   'unknown', 'production', 'development'
	AppEnvironment func(value string) kvp.Field

	// ItemsAccepted returns a kvp.Field with the gh.copilot_telemetry.items_accepted key and the value you provide.
	//
	// Number of items which have been accepted.
	//
	// Type: int
	//
	// Examples:
	//   5, 12
	ItemsAccepted func(value int) kvp.Field

	// ItemsReceived returns a kvp.Field with the gh.copilot_telemetry.items_received key and the value you provide.
	//
	// Number of items which have been received.
	//
	// Type: int
	//
	// Examples:
	//   8, 16
	ItemsReceived func(value int) kvp.Field

	// BadItemIndices returns a kvp.Field with the gh.copilot_telemetry.bad_item_indices key and the value you provide.
	//
	// Indices of the bad items.
	//
	// Type: int[]
	//
	// Examples:
	//   7, 42, 666], [100, 200, 300
	BadItemIndices func(value ...int) kvp.Field

	// BadItems returns a kvp.Field with the gh.copilot_telemetry.bad_items key and the value you provide.
	//
	// Number of bad items.
	//
	// Type: int
	//
	// Examples:
	//   3, 9
	BadItems func(value int) kvp.Field

	// TotalItems returns a kvp.Field with the gh.copilot_telemetry.total_items key and the value you provide.
	//
	// Total number of items.
	//
	// Type: int
	//
	// Examples:
	//   800, 1000000
	TotalItems func(value int) kvp.Field

	// PercentBadItems returns a kvp.Field with the gh.copilot_telemetry.percent_bad_items key and the value you provide.
	//
	// Bad items divided by total items.
	//
	// Type: double
	//
	// Examples:
	//   0.314, 0.662607
	PercentBadItems func(value float64) kvp.Field
}

// This document specifies common exception metadata specific the copilot-telemetry-service
var GhCopilotTelemetry = ghCopilotTelemetry{
	AppEnvironment: func(value string) kvp.Field {
		return kvp.String("gh.copilot_telemetry.app_environment", value)
	},

	ItemsAccepted: func(value int) kvp.Field {
		return kvp.Int("gh.copilot_telemetry.items_accepted", value)
	},

	ItemsReceived: func(value int) kvp.Field {
		return kvp.Int("gh.copilot_telemetry.items_received", value)
	},

	BadItemIndices: func(value ...int) kvp.Field {
		return kvp.Ints("gh.copilot_telemetry.bad_item_indices", value)
	},

	BadItems: func(value int) kvp.Field {
		return kvp.Int("gh.copilot_telemetry.bad_items", value)
	},

	TotalItems: func(value int) kvp.Field {
		return kvp.Int("gh.copilot_telemetry.total_items", value)
	},

	PercentBadItems: func(value float64) kvp.Field {
		return kvp.Float64("gh.copilot_telemetry.percent_bad_items", value)
	},
}

// This document specifies common exception metadata specific to internal GitHub systems.
type ghException struct {
	// Rollup returns a kvp.Field with the gh.exception.rollup key and the value you provide.
	//
	// A fingerprint that uniquely identifies the exception and the callsite
	//
	// Type: string
	//
	// Examples:
	//   'ab08761803ea2dec3dc1817f108cd06a9de97b879fef0900e505f8336747e674'
	Rollup func(value string) kvp.Field

	// Project returns a kvp.Field with the gh.exception.project key and the value you provide.
	//
	// The category this exception belongs to.  In Sentry this will be the project name.  This is
	// commonly the application name, but some applications have multiple projects for different
	// purposes.
	//
	// Type: string
	//
	// Examples:
	//   'github', 'github-user', 'nines'
	Project func(value string) kvp.Field
}

// This document specifies common exception metadata specific to internal GitHub systems.
var GhException = ghException{
	Rollup: func(value string) kvp.Field {
		return kvp.String("gh.exception.rollup", value)
	},

	Project: func(value string) kvp.Field {
		return kvp.String("gh.exception.project", value)
	},
}

// failbotg exposes an API that accepts exceptions and reports them to sentry and fluent-bit.
type ghFailbotg struct {
	// MessagePayloadBytes returns a kvp.Field with the gh.failbotg.message.payload_bytes key and the value you provide.
	//
	// The size of the message payload in bytes
	//
	// Type: int
	//
	// Examples:
	//   1024
	MessagePayloadBytes func(value int) kvp.Field

	// PayloadUncompressedBytes returns a kvp.Field with the gh.failbotg.payload_uncompressed_bytes key and the value you provide.
	//
	// The size of the uncompressed payload in bytes
	//
	// Type: int
	//
	// Examples:
	//   2048
	PayloadUncompressedBytes func(value int) kvp.Field

	// DestinationName returns a kvp.Field with the gh.failbotg.destination.name key and the value you provide.
	//
	// The name of the exception destination
	//
	// Type: string
	//
	// Examples:
	//   'fluent-bit', 'sentry'
	DestinationName func(value string) kvp.Field

	// MessageId returns a kvp.Field with the gh.failbotg.message.id key and the value you provide.
	//
	// the ID of the message
	//
	// Type: string
	//
	// Examples:
	//   'unique-id'
	MessageId func(value string) kvp.Field
}

// failbotg exposes an API that accepts exceptions and reports them to sentry and fluent-bit.
var GhFailbotg = ghFailbotg{
	MessagePayloadBytes: func(value int) kvp.Field {
		return kvp.Int("gh.failbotg.message.payload_bytes", value)
	},

	PayloadUncompressedBytes: func(value int) kvp.Field {
		return kvp.Int("gh.failbotg.payload_uncompressed_bytes", value)
	},

	DestinationName: func(value string) kvp.Field {
		return kvp.String("gh.failbotg.destination.name", value)
	},

	MessageId: func(value string) kvp.Field {
		return kvp.String("gh.failbotg.message.id", value)
	},
}

// This document specifies common metadata specific to internal GitHub systems.
type gh struct {
	// RequestId returns a kvp.Field with the gh.request_id key and the value you provide.
	//
	// A received or generated GitHub Request-ID applicable to this trace.
	//
	// Type: string
	//
	// Requirement Level: Conditionally Required - If a client receives this attribute from an upstream request, then this attribute MUST be set to the received value. Otherwise, the client SHOULD generate a UUIDv4 for this attribute. Clients SHOULD NOT generate a new UUIDv4 in some circumstances, such as long-running background jobs which do not correlate to a single logical 'request' - or more generally, whenever a singular `github.request_id` would cause confusion. HTTP Clients SHOULD propagate this request in the `X-GitHub-RequestId` header, but that is otherwise out of scope for this document.
	//
	// Examples:
	//   'C661:2D45:1644B4E:2D936BB:60B6415F', 'a0e5b7e4-91da-4845-9914-9251d907e060'
	RequestId func(value string) kvp.Field

	// VisitorId returns a kvp.Field with the gh.visitor_id key and the value you provide.
	//
	// Analytics identifier, this is used for tracking users across different github.com domains. This
	// has also been referenced as octolytics_id in the past.
	//
	// Type: string
	//
	// Examples:
	//   'GH1.1.1234567899.9987654321'
	VisitorId func(value string) kvp.Field

	// Tenant returns a kvp.Field with the gh.tenant key and the value you provide.
	//
	// The GitHub Tenant applicable to this trace. In Proxima, this is the GitHub customer tenant. In
	// Dotcom this is 'dotcom'. In GHES, this is the customer account.
	//
	// Type: string
	//
	// Examples:
	//   'dotcom', 'contoso'
	Tenant func(value string) kvp.Field

	// OrgName returns a kvp.Field with the gh.org.name key and the value you provide.
	//
	// Name of a GitHub organization as returned by the [Organizations
	// API](https://docs.github.com/en/rest/reference/orgs#get-an-organization)
	//
	// Type: string
	//
	// Examples:
	//   'github', 'apache', 'tensorflow'
	OrgName func(value string) kvp.Field

	// OrgId returns a kvp.Field with the gh.org.id key and the value you provide.
	//
	// ID of a GitHub organization as returned by the [Organizations
	// API](https://docs.github.com/en/rest/reference/orgs#get-an-organization)
	//
	// Type: int
	OrgId func(value int) kvp.Field

	// RepoName returns a kvp.Field with the gh.repo.name key and the value you provide.
	//
	// Name of a GitHub repository as returned by the [Repositories
	// API](https://docs.github.com/en/rest/reference/repos#get-a-repository)
	//
	// Type: string
	//
	// Examples:
	//   'github', 'kafka', 'tensorflow'
	RepoName func(value string) kvp.Field

	// RepoId returns a kvp.Field with the gh.repo.id key and the value you provide.
	//
	// ID of a GitHub repository as returned by the [Repositories
	// API](https://docs.github.com/en/rest/reference/repos#get-a-repository)
	//
	// Type: int
	RepoId func(value int) kvp.Field

	// RepoNameWithOwner returns a kvp.Field with the gh.repo.name_with_owner key and the value you provide.
	//
	// Name of a GitHub repository with the owner as returned as `full_name` by the [Repositories
	// API](https://docs.github.com/en/rest/reference/repos#get-a-repository)"
	//
	// Type: string
	//
	// Examples:
	//   'github/github', 'apache/kafka', 'tensorflow/tensorflow'
	RepoNameWithOwner func(value string) kvp.Field

	// OwnerId returns a kvp.Field with the gh.owner.id key and the value you provide.
	//
	// ID of a GitHub repository owner. Can be an org or a user. Useful for systems that act on the
	// owner without a need to distinguish whether the owner is an org or a user.
	//
	// Type: int
	OwnerId func(value int) kvp.Field

	// OwnerLogin returns a kvp.Field with the gh.owner.login key and the value you provide.
	//
	// Name of a GitHub repository owner. Can be an org or a user. Useful for systems that act on the
	// owner without a need to distinguish whether the owner is an org or a user.
	//
	// Type: string
	//
	// Examples:
	//   'github', 'apache', 'tensorflow', 'aybabtme'
	OwnerLogin func(value string) kvp.Field

	// UserId returns a kvp.Field with the gh.user.id key and the value you provide.
	//
	// ID of a GitHub user as returned by the [Users
	// API](https://docs.github.com/en/rest/reference/users#get-a-single-user)
	//
	// Type: int
	UserId func(value int) kvp.Field
}

// This document specifies common metadata specific to internal GitHub systems.
var Gh = gh{
	RequestId: func(value string) kvp.Field {
		return kvp.String("gh.request_id", value)
	},

	VisitorId: func(value string) kvp.Field {
		return kvp.String("gh.visitor_id", value)
	},

	Tenant: func(value string) kvp.Field {
		return kvp.String("gh.tenant", value)
	},

	OrgName: func(value string) kvp.Field {
		return kvp.String("gh.org.name", value)
	},

	OrgId: func(value int) kvp.Field {
		return kvp.Int("gh.org.id", value)
	},

	RepoName: func(value string) kvp.Field {
		return kvp.String("gh.repo.name", value)
	},

	RepoId: func(value int) kvp.Field {
		return kvp.Int("gh.repo.id", value)
	},

	RepoNameWithOwner: func(value string) kvp.Field {
		return kvp.String("gh.repo.name_with_owner", value)
	},

	OwnerId: func(value int) kvp.Field {
		return kvp.Int("gh.owner.id", value)
	},

	OwnerLogin: func(value string) kvp.Field {
		return kvp.String("gh.owner.login", value)
	},

	UserId: func(value int) kvp.Field {
		return kvp.Int("gh.user.id", value)
	},
}

// This document specifies common attribute names for generic operations that may be used in a
// GitHub service.  These may be used for jobs or any other operation where the status of the
// operation is important.
type ghOperation struct {
	// Name returns a kvp.Field with the gh.operation.name key and the value you provide.
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
	Name func(value string) kvp.Field

	// Duration returns a kvp.Field with the gh.operation.duration key and the value you provide.
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
	Duration func(value float64) kvp.Field
}

// This document specifies common attribute names for generic operations that may be used in a
// GitHub service.  These may be used for jobs or any other operation where the status of the
// operation is important.
var GhOperation = ghOperation{
	Name: func(value string) kvp.Field {
		return kvp.String("gh.operation.name", value)
	},

	Duration: func(value float64) kvp.Field {
		return kvp.Float64("gh.operation.duration", value)
	},
}

// This document specifies common metadata specific to the Runtime product.
type ghRuntime struct {
	// DeployId returns a kvp.Field with the gh.runtime.deploy_id key and the value you provide.
	//
	// The ID of a Runtime deployment.
	//
	// Type: int
	DeployId func(value int) kvp.Field
}

// This document specifies common metadata specific to the Runtime product.
var GhRuntime = ghRuntime{
	DeployId: func(value int) kvp.Field {
		return kvp.Int("gh.runtime.deploy_id", value)
	},
}

// These are attributes specifically used in Twirp RPCs  traces
// (https://twitchtv.github.io/twirp/docs/spec_v5.html). These are generally used in automatic
// instrumentation that might be setup with github/github-telemetry-<lang> tracing needs for Twirp
// RPCs.
type ghTwirp struct {

	// Kind struct
	//
	// The kind of RPCs operation being performed.
	//
	// Type: Enum
	//
	// Requirement Level: Required
	//
	// Note:
	// The kind of RPCs to help determine what type of Twirp Hook is setup for the trace.
	Kind struct {
		// ServerHooks is a kvp.Field with key "gh.twirp.kind" and value "ServerHooks"
		//
		// Twirp tracing hook is defined by a *twirp.ServerHooks type
		ServerHooks kvp.Field

		// ClientHooks is a kvp.Field with key "gh.twirp.kind" and value "ClientHooks"
		//
		// Twirp tracing hook is defined by *twirp.ClientHooks type
		ClientHooks kvp.Field
	}

	// PackageName returns a kvp.Field with the gh.twirp.package.name key and the value you provide.
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
	PackageName func(value string) kvp.Field

	// ServiceName returns a kvp.Field with the gh.twirp.service.name key and the value you provide.
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
	ServiceName func(value string) kvp.Field
}

// These are attributes specifically used in Twirp RPCs  traces
// (https://twitchtv.github.io/twirp/docs/spec_v5.html). These are generally used in automatic
// instrumentation that might be setup with github/github-telemetry-<lang> tracing needs for Twirp
// RPCs.
var GhTwirp = ghTwirp{
	Kind: struct {
		ServerHooks kvp.Field
		ClientHooks kvp.Field
	}{
		ServerHooks: kvp.String("gh.twirp.kind", "ServerHooks"),
		ClientHooks: kvp.String("gh.twirp.kind", "ClientHooks"),
	},

	PackageName: func(value string) kvp.Field {
		return kvp.String("gh.twirp.package.name", value)
	},

	ServiceName: func(value string) kvp.Field {
		return kvp.String("gh.twirp.service.name", value)
	},
}

// This document defines semantic conventions for HTTP client and server Spans.
type http struct {
	// Method returns a kvp.Field with the http.method key and the value you provide.
	//
	// HTTP request method.
	//
	// Type: string
	//
	// Requirement Level: Required
	//
	// Examples:
	//   'GET', 'POST', 'HEAD'
	Method func(value string) kvp.Field

	// StatusCode returns a kvp.Field with the http.status_code key and the value you provide.
	//
	// [HTTP response status code](https://tools.ietf.org/html/rfc7231#section-6).
	//
	// Type: int
	//
	// Requirement Level: Conditionally Required - If and only if one was received/sent.
	//
	// Examples:
	//   200
	StatusCode func(value int) kvp.Field

	// Flavor struct
	//
	// Kind of HTTP protocol used.
	//
	// Type: Enum
	//
	// Note:
	// If `net.transport` is not specified, it can be assumed to be `IP.TCP` except if `http.flavor`
	// is `QUIC`, in which case `IP.UDP` is assumed.
	Flavor struct {
		// Http10 is a kvp.Field with key "http.flavor" and value "1.0"
		//
		// HTTP/1.0
		Http10 kvp.Field

		// Http11 is a kvp.Field with key "http.flavor" and value "1.1"
		//
		// HTTP/1.1
		Http11 kvp.Field

		// Http20 is a kvp.Field with key "http.flavor" and value "2.0"
		//
		// HTTP/2
		Http20 kvp.Field

		// Http30 is a kvp.Field with key "http.flavor" and value "3.0"
		//
		// HTTP/3
		Http30 kvp.Field

		// Spdy is a kvp.Field with key "http.flavor" and value "SPDY"
		//
		// SPDY protocol
		Spdy kvp.Field

		// Quic is a kvp.Field with key "http.flavor" and value "QUIC"
		//
		// QUIC protocol
		Quic kvp.Field

		// CustomValue returns a kvp.Field with key "http.flavor" and the value you pass in.
		CustomValue func(value string) kvp.Field
	}

	// UserAgent returns a kvp.Field with the http.user_agent key and the value you provide.
	//
	// Value of the [HTTP User-Agent](https://www.rfc-editor.org/rfc/rfc9110.html#field.user-agent)
	// header sent by the client.
	//
	// Type: string
	//
	// Examples:
	//   'CERN-LineMode/2.15 libwww/2.17b3'
	UserAgent func(value string) kvp.Field

	// RequestContentLength returns a kvp.Field with the http.request_content_length key and the value you provide.
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
	RequestContentLength func(value int) kvp.Field

	// ResponseContentLength returns a kvp.Field with the http.response_content_length key and the value you provide.
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
	ResponseContentLength func(value int) kvp.Field
}

// This document defines semantic conventions for HTTP client and server Spans.
var Http = http{
	Method: func(value string) kvp.Field {
		return kvp.String("http.method", value)
	},

	StatusCode: func(value int) kvp.Field {
		return kvp.Int("http.status_code", value)
	},

	Flavor: struct {
		Http10      kvp.Field
		Http11      kvp.Field
		Http20      kvp.Field
		Http30      kvp.Field
		Spdy        kvp.Field
		Quic        kvp.Field
		CustomValue func(value string) kvp.Field
	}{
		Http10: kvp.String("http.flavor", "1.0"),
		Http11: kvp.String("http.flavor", "1.1"),
		Http20: kvp.String("http.flavor", "2.0"),
		Http30: kvp.String("http.flavor", "3.0"),
		Spdy:   kvp.String("http.flavor", "SPDY"),
		Quic:   kvp.String("http.flavor", "QUIC"),
		CustomValue: func(value string) kvp.Field {
			return kvp.String("http.flavor", value)
		},
	},

	UserAgent: func(value string) kvp.Field {
		return kvp.String("http.user_agent", value)
	},

	RequestContentLength: func(value int) kvp.Field {
		return kvp.Int("http.request_content_length", value)
	},

	ResponseContentLength: func(value int) kvp.Field {
		return kvp.Int("http.response_content_length", value)
	},
}

// Semantic Convention for HTTP Client
type httpClient struct {
	// Url returns a kvp.Field with the http.url key and the value you provide.
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
	Url func(value string) kvp.Field

	// RetryCount returns a kvp.Field with the http.retry_count key and the value you provide.
	//
	// The ordinal number of request re-sending attempt.
	//
	// Type: int
	//
	// Requirement Level: Recommended
	//
	// Examples:
	//   3
	RetryCount func(value int) kvp.Field
}

// Semantic Convention for HTTP Client
var HttpClient = httpClient{
	Url: func(value string) kvp.Field {
		return kvp.String("http.url", value)
	},

	RetryCount: func(value int) kvp.Field {
		return kvp.Int("http.retry_count", value)
	},
}

// Semantic Convention for HTTP Server
type httpServer struct {
	// Scheme returns a kvp.Field with the http.scheme key and the value you provide.
	//
	// The URI scheme identifying the used protocol.
	//
	// Type: string
	//
	// Requirement Level: Required
	//
	// Examples:
	//   'http', 'https'
	Scheme func(value string) kvp.Field

	// Target returns a kvp.Field with the http.target key and the value you provide.
	//
	// The full request target as passed in a HTTP request line or equivalent.
	//
	// Type: string
	//
	// Requirement Level: Required
	//
	// Examples:
	//   '/path/12314/?q=ddds'
	Target func(value string) kvp.Field

	// Route returns a kvp.Field with the http.route key and the value you provide.
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
	Route func(value string) kvp.Field

	// ClientIp returns a kvp.Field with the http.client_ip key and the value you provide.
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
	ClientIp func(value string) kvp.Field
}

// Semantic Convention for HTTP Server
var HttpServer = httpServer{
	Scheme: func(value string) kvp.Field {
		return kvp.String("http.scheme", value)
	},

	Target: func(value string) kvp.Field {
		return kvp.String("http.target", value)
	},

	Route: func(value string) kvp.Field {
		return kvp.String("http.route", value)
	},

	ClientIp: func(value string) kvp.Field {
		return kvp.String("http.client_ip", value)
	},
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
	// TableNames returns a kvp.Field with the aws.dynamodb.table_names key and the value you provide.
	//
	// The keys in the `RequestItems` object field.
	//
	// Type: string[]
	//
	// Examples:
	//   'Users', 'Cats'
	TableNames func(value ...string) kvp.Field

	// ConsumedCapacity returns a kvp.Field with the aws.dynamodb.consumed_capacity key and the value you provide.
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
	ConsumedCapacity func(value ...string) kvp.Field

	// ItemCollectionMetrics returns a kvp.Field with the aws.dynamodb.item_collection_metrics key and the value you provide.
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
	ItemCollectionMetrics func(value string) kvp.Field

	// ProvisionedReadCapacity returns a kvp.Field with the aws.dynamodb.provisioned_read_capacity key and the value you provide.
	//
	// The value of the `ProvisionedThroughput.ReadCapacityUnits` request parameter.
	//
	// Type: double
	//
	// Examples:
	//   1.0, 2.0
	ProvisionedReadCapacity func(value float64) kvp.Field

	// ProvisionedWriteCapacity returns a kvp.Field with the aws.dynamodb.provisioned_write_capacity key and the value you provide.
	//
	// The value of the `ProvisionedThroughput.WriteCapacityUnits` request parameter.
	//
	// Type: double
	//
	// Examples:
	//   1.0, 2.0
	ProvisionedWriteCapacity func(value float64) kvp.Field

	// ConsistentRead returns a kvp.Field with the aws.dynamodb.consistent_read key and the value you provide.
	//
	// The value of the `ConsistentRead` request parameter.
	//
	// Type: boolean
	ConsistentRead func(value bool) kvp.Field

	// Projection returns a kvp.Field with the aws.dynamodb.projection key and the value you provide.
	//
	// The value of the `ProjectionExpression` request parameter.
	//
	// Type: string
	//
	// Examples:
	//   'Title', 'Title, Price, Color', 'Title, Description, RelatedItems, ProductReviews'
	Projection func(value string) kvp.Field

	// Limit returns a kvp.Field with the aws.dynamodb.limit key and the value you provide.
	//
	// The value of the `Limit` request parameter.
	//
	// Type: int
	//
	// Examples:
	//   10
	Limit func(value int) kvp.Field

	// AttributesToGet returns a kvp.Field with the aws.dynamodb.attributes_to_get key and the value you provide.
	//
	// The value of the `AttributesToGet` request parameter.
	//
	// Type: string[]
	//
	// Examples:
	//   'lives', 'id'
	AttributesToGet func(value ...string) kvp.Field

	// IndexName returns a kvp.Field with the aws.dynamodb.index_name key and the value you provide.
	//
	// The value of the `IndexName` request parameter.
	//
	// Type: string
	//
	// Examples:
	//   'name_to_group'
	IndexName func(value string) kvp.Field

	// Select returns a kvp.Field with the aws.dynamodb.select key and the value you provide.
	//
	// The value of the `Select` request parameter.
	//
	// Type: string
	//
	// Examples:
	//   'ALL_ATTRIBUTES', 'COUNT'
	Select func(value string) kvp.Field
}

// Attributes that exist for multiple DynamoDB request types.
var DynamodbShared = dynamodbShared{
	TableNames: func(value ...string) kvp.Field {
		return kvp.Strings("aws.dynamodb.table_names", value)
	},

	ConsumedCapacity: func(value ...string) kvp.Field {
		return kvp.Strings("aws.dynamodb.consumed_capacity", value)
	},

	ItemCollectionMetrics: func(value string) kvp.Field {
		return kvp.String("aws.dynamodb.item_collection_metrics", value)
	},

	ProvisionedReadCapacity: func(value float64) kvp.Field {
		return kvp.Float64("aws.dynamodb.provisioned_read_capacity", value)
	},

	ProvisionedWriteCapacity: func(value float64) kvp.Field {
		return kvp.Float64("aws.dynamodb.provisioned_write_capacity", value)
	},

	ConsistentRead: func(value bool) kvp.Field {
		return kvp.Bool("aws.dynamodb.consistent_read", value)
	},

	Projection: func(value string) kvp.Field {
		return kvp.String("aws.dynamodb.projection", value)
	},

	Limit: func(value int) kvp.Field {
		return kvp.Int("aws.dynamodb.limit", value)
	},

	AttributesToGet: func(value ...string) kvp.Field {
		return kvp.Strings("aws.dynamodb.attributes_to_get", value)
	},

	IndexName: func(value string) kvp.Field {
		return kvp.String("aws.dynamodb.index_name", value)
	},

	Select: func(value string) kvp.Field {
		return kvp.String("aws.dynamodb.select", value)
	},
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
	// GlobalSecondaryIndexes returns a kvp.Field with the aws.dynamodb.global_secondary_indexes key and the value you provide.
	//
	// The JSON-serialized value of each item of the `GlobalSecondaryIndexes` request field
	//
	// Type: string[]
	//
	// Examples:
	//   '{ "IndexName": "string", "KeySchema": [ { "AttributeName": "string", "KeyType": "string" } ],
	// "Projection": { "NonKeyAttributes": [ "string" ], "ProjectionType": "string" },
	// "ProvisionedThroughput": { "ReadCapacityUnits": number, "WriteCapacityUnits": number } }'
	GlobalSecondaryIndexes func(value ...string) kvp.Field

	// LocalSecondaryIndexes returns a kvp.Field with the aws.dynamodb.local_secondary_indexes key and the value you provide.
	//
	// The JSON-serialized value of each item of the `LocalSecondaryIndexes` request field.
	//
	// Type: string[]
	//
	// Examples:
	//   '{ "IndexArn": "string", "IndexName": "string", "IndexSizeBytes": number, "ItemCount": number,
	// "KeySchema": [ { "AttributeName": "string", "KeyType": "string" } ], "Projection": {
	// "NonKeyAttributes": [ "string" ], "ProjectionType": "string" } }'
	LocalSecondaryIndexes func(value ...string) kvp.Field
}

// DynamoDB.CreateTable
var DynamodbCreatetable = dynamodbCreatetable{
	GlobalSecondaryIndexes: func(value ...string) kvp.Field {
		return kvp.Strings("aws.dynamodb.global_secondary_indexes", value)
	},

	LocalSecondaryIndexes: func(value ...string) kvp.Field {
		return kvp.Strings("aws.dynamodb.local_secondary_indexes", value)
	},
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
	// ExclusiveStartTable returns a kvp.Field with the aws.dynamodb.exclusive_start_table key and the value you provide.
	//
	// The value of the `ExclusiveStartTableName` request parameter.
	//
	// Type: string
	//
	// Examples:
	//   'Users', 'CatsTable'
	ExclusiveStartTable func(value string) kvp.Field

	// TableCount returns a kvp.Field with the aws.dynamodb.table_count key and the value you provide.
	//
	// The the number of items in the `TableNames` response parameter.
	//
	// Type: int
	//
	// Examples:
	//   20
	TableCount func(value int) kvp.Field
}

// DynamoDB.ListTables
var DynamodbListtables = dynamodbListtables{
	ExclusiveStartTable: func(value string) kvp.Field {
		return kvp.String("aws.dynamodb.exclusive_start_table", value)
	},

	TableCount: func(value int) kvp.Field {
		return kvp.Int("aws.dynamodb.table_count", value)
	},
}

// DynamoDB.PutItem
type dynamodbPutitem struct {
}

// DynamoDB.PutItem
var DynamodbPutitem = dynamodbPutitem{}

// DynamoDB.Query
type dynamodbQuery struct {
	// ScanForward returns a kvp.Field with the aws.dynamodb.scan_forward key and the value you provide.
	//
	// The value of the `ScanIndexForward` request parameter.
	//
	// Type: boolean
	ScanForward func(value bool) kvp.Field
}

// DynamoDB.Query
var DynamodbQuery = dynamodbQuery{
	ScanForward: func(value bool) kvp.Field {
		return kvp.Bool("aws.dynamodb.scan_forward", value)
	},
}

// DynamoDB.Scan
type dynamodbScan struct {
	// Segment returns a kvp.Field with the aws.dynamodb.segment key and the value you provide.
	//
	// The value of the `Segment` request parameter.
	//
	// Type: int
	//
	// Examples:
	//   10
	Segment func(value int) kvp.Field

	// TotalSegments returns a kvp.Field with the aws.dynamodb.total_segments key and the value you provide.
	//
	// The value of the `TotalSegments` request parameter.
	//
	// Type: int
	//
	// Examples:
	//   100
	TotalSegments func(value int) kvp.Field

	// Count returns a kvp.Field with the aws.dynamodb.count key and the value you provide.
	//
	// The value of the `Count` response parameter.
	//
	// Type: int
	//
	// Examples:
	//   10
	Count func(value int) kvp.Field

	// ScannedCount returns a kvp.Field with the aws.dynamodb.scanned_count key and the value you provide.
	//
	// The value of the `ScannedCount` response parameter.
	//
	// Type: int
	//
	// Examples:
	//   50
	ScannedCount func(value int) kvp.Field
}

// DynamoDB.Scan
var DynamodbScan = dynamodbScan{
	Segment: func(value int) kvp.Field {
		return kvp.Int("aws.dynamodb.segment", value)
	},

	TotalSegments: func(value int) kvp.Field {
		return kvp.Int("aws.dynamodb.total_segments", value)
	},

	Count: func(value int) kvp.Field {
		return kvp.Int("aws.dynamodb.count", value)
	},

	ScannedCount: func(value int) kvp.Field {
		return kvp.Int("aws.dynamodb.scanned_count", value)
	},
}

// DynamoDB.UpdateItem
type dynamodbUpdateitem struct {
}

// DynamoDB.UpdateItem
var DynamodbUpdateitem = dynamodbUpdateitem{}

// DynamoDB.UpdateTable
type dynamodbUpdatetable struct {
	// AttributeDefinitions returns a kvp.Field with the aws.dynamodb.attribute_definitions key and the value you provide.
	//
	// The JSON-serialized value of each item in the `AttributeDefinitions` request field.
	//
	// Type: string[]
	//
	// Examples:
	//   '{ "AttributeName": "string", "AttributeType": "string" }'
	AttributeDefinitions func(value ...string) kvp.Field

	// GlobalSecondaryIndexUpdates returns a kvp.Field with the aws.dynamodb.global_secondary_index_updates key and the value you provide.
	//
	// The JSON-serialized value of each item in the the `GlobalSecondaryIndexUpdates` request field.
	//
	// Type: string[]
	//
	// Examples:
	//   '{ "Create": { "IndexName": "string", "KeySchema": [ { "AttributeName": "string", "KeyType":
	// "string" } ], "Projection": { "NonKeyAttributes": [ "string" ], "ProjectionType": "string" },
	// "ProvisionedThroughput": { "ReadCapacityUnits": number, "WriteCapacityUnits": number } }'
	GlobalSecondaryIndexUpdates func(value ...string) kvp.Field
}

// DynamoDB.UpdateTable
var DynamodbUpdatetable = dynamodbUpdatetable{
	AttributeDefinitions: func(value ...string) kvp.Field {
		return kvp.Strings("aws.dynamodb.attribute_definitions", value)
	},

	GlobalSecondaryIndexUpdates: func(value ...string) kvp.Field {
		return kvp.Strings("aws.dynamodb.global_secondary_index_updates", value)
	},
}

// This document defines semantic conventions to apply when instrumenting the GraphQL
// implementation. They map GraphQL operations to attributes on a Span.
type graphql struct {
	// OperationName returns a kvp.Field with the graphql.operation.name key and the value you provide.
	//
	// The name of the operation being executed.
	//
	// Type: string
	//
	// Examples:
	//   'findBookById'
	OperationName func(value string) kvp.Field

	// OperationType struct
	//
	// The type of the operation being executed.
	//
	// Type: Enum
	//
	// Examples:
	//   'query', 'mutation', 'subscription'
	OperationType struct {
		// Query is a kvp.Field with key "graphql.operation.type" and value "query"
		//
		// GraphQL query
		Query kvp.Field

		// Mutation is a kvp.Field with key "graphql.operation.type" and value "mutation"
		//
		// GraphQL mutation
		Mutation kvp.Field

		// Subscription is a kvp.Field with key "graphql.operation.type" and value "subscription"
		//
		// GraphQL subscription
		Subscription kvp.Field
	}

	// Document returns a kvp.Field with the graphql.document key and the value you provide.
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
	Document func(value string) kvp.Field
}

// This document defines semantic conventions to apply when instrumenting the GraphQL
// implementation. They map GraphQL operations to attributes on a Span.
var Graphql = graphql{
	OperationName: func(value string) kvp.Field {
		return kvp.String("graphql.operation.name", value)
	},

	OperationType: struct {
		Query        kvp.Field
		Mutation     kvp.Field
		Subscription kvp.Field
	}{
		Query:        kvp.String("graphql.operation.type", "query"),
		Mutation:     kvp.String("graphql.operation.type", "mutation"),
		Subscription: kvp.String("graphql.operation.type", "subscription"),
	},

	Document: func(value string) kvp.Field {
		return kvp.String("graphql.document", value)
	},
}

// This document defines the attributes used in messaging systems.
type messaging struct {
	// System returns a kvp.Field with the messaging.system key and the value you provide.
	//
	// A string identifying the messaging system.
	//
	// Type: string
	//
	// Requirement Level: Required
	//
	// Examples:
	//   'kafka', 'rabbitmq', 'rocketmq', 'activemq', 'AmazonSQS'
	System func(value string) kvp.Field

	// Destination returns a kvp.Field with the messaging.destination key and the value you provide.
	//
	// The message destination name. This might be equal to the span name but is required nevertheless.
	//
	// Type: string
	//
	// Requirement Level: Required
	//
	// Examples:
	//   'MyQueue', 'MyTopic'
	Destination func(value string) kvp.Field

	// DestinationKind struct
	//
	// The kind of message destination
	//
	// Type: Enum
	//
	// Requirement Level: Conditionally Required - If the message destination is either a `queue` or `topic`.
	DestinationKind struct {
		// Queue is a kvp.Field with key "messaging.destination_kind" and value "queue"
		//
		// A message sent to a queue
		Queue kvp.Field

		// Topic is a kvp.Field with key "messaging.destination_kind" and value "topic"
		//
		// A message sent to a topic
		Topic kvp.Field
	}

	// TempDestination returns a kvp.Field with the messaging.temp_destination key and the value you provide.
	//
	// A boolean that is true if the message destination is temporary.
	//
	// Type: boolean
	//
	// Requirement Level: Conditionally Required - If value is `true`. When missing, the value is assumed to be `false`.
	TempDestination func(value bool) kvp.Field

	// Protocol returns a kvp.Field with the messaging.protocol key and the value you provide.
	//
	// The name of the transport protocol.
	//
	// Type: string
	//
	// Examples:
	//   'AMQP', 'MQTT'
	Protocol func(value string) kvp.Field

	// ProtocolVersion returns a kvp.Field with the messaging.protocol_version key and the value you provide.
	//
	// The version of the transport protocol.
	//
	// Type: string
	//
	// Examples:
	//   '0.9.1'
	ProtocolVersion func(value string) kvp.Field

	// Url returns a kvp.Field with the messaging.url key and the value you provide.
	//
	// Connection string.
	//
	// Type: string
	//
	// Examples:
	//   'tibjmsnaming://localhost:7222', 'https://queue.amazonaws.com/80398EXAMPLE/MyQueue'
	Url func(value string) kvp.Field

	// MessageId returns a kvp.Field with the messaging.message_id key and the value you provide.
	//
	// A value used by the messaging system as an identifier for the message, represented as a string.
	//
	// Type: string
	//
	// Examples:
	//   '452a7c7c7c7048c2f887f61572b18fc2'
	MessageId func(value string) kvp.Field

	// ConversationId returns a kvp.Field with the messaging.conversation_id key and the value you provide.
	//
	// The [conversation ID](#conversations) identifying the conversation to which the message belongs,
	// represented as a string. Sometimes called "Correlation ID".
	//
	// Type: string
	//
	// Examples:
	//   'MyConversationId'
	ConversationId func(value string) kvp.Field

	// MessagePayloadSizeBytes returns a kvp.Field with the messaging.message_payload_size_bytes key and the value you provide.
	//
	// The (uncompressed) size of the message payload in bytes. Also use this attribute if it is unknown
	// whether the compressed or uncompressed payload size is reported.
	//
	// Type: int
	//
	// Examples:
	//   2738
	MessagePayloadSizeBytes func(value int) kvp.Field

	// MessagePayloadCompressedSizeBytes returns a kvp.Field with the messaging.message_payload_compressed_size_bytes key and the value you provide.
	//
	// The compressed size of the message payload in bytes.
	//
	// Type: int
	//
	// Examples:
	//   2048
	MessagePayloadCompressedSizeBytes func(value int) kvp.Field
}

// This document defines the attributes used in messaging systems.
var Messaging = messaging{
	System: func(value string) kvp.Field {
		return kvp.String("messaging.system", value)
	},

	Destination: func(value string) kvp.Field {
		return kvp.String("messaging.destination", value)
	},

	DestinationKind: struct {
		Queue kvp.Field
		Topic kvp.Field
	}{
		Queue: kvp.String("messaging.destination_kind", "queue"),
		Topic: kvp.String("messaging.destination_kind", "topic"),
	},

	TempDestination: func(value bool) kvp.Field {
		return kvp.Bool("messaging.temp_destination", value)
	},

	Protocol: func(value string) kvp.Field {
		return kvp.String("messaging.protocol", value)
	},

	ProtocolVersion: func(value string) kvp.Field {
		return kvp.String("messaging.protocol_version", value)
	},

	Url: func(value string) kvp.Field {
		return kvp.String("messaging.url", value)
	},

	MessageId: func(value string) kvp.Field {
		return kvp.String("messaging.message_id", value)
	},

	ConversationId: func(value string) kvp.Field {
		return kvp.String("messaging.conversation_id", value)
	},

	MessagePayloadSizeBytes: func(value int) kvp.Field {
		return kvp.Int("messaging.message_payload_size_bytes", value)
	},

	MessagePayloadCompressedSizeBytes: func(value int) kvp.Field {
		return kvp.Int("messaging.message_payload_compressed_size_bytes", value)
	},
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

	// Operation struct
	//
	// A string identifying the kind of message consumption as defined in the [Operation
	// names](#operation-names) section above. If the operation is "send", this attribute MUST NOT be
	// set, since the operation can be inferred from the span kind in that case.
	//
	// Type: Enum
	Operation struct {
		// Receive is a kvp.Field with key "messaging.operation" and value "receive"
		//
		// receive
		Receive kvp.Field

		// Process is a kvp.Field with key "messaging.operation" and value "process"
		//
		// process
		Process kvp.Field
	}

	// ConsumerId returns a kvp.Field with the messaging.consumer_id key and the value you provide.
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
	ConsumerId func(value string) kvp.Field
}

// Semantic convention for a consumer of messages received from a messaging system
var MessagingConsumer = messagingConsumer{
	Operation: struct {
		Receive kvp.Field
		Process kvp.Field
	}{
		Receive: kvp.String("messaging.operation", "receive"),
		Process: kvp.String("messaging.operation", "process"),
	},

	ConsumerId: func(value string) kvp.Field {
		return kvp.String("messaging.consumer_id", value)
	},
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
	// RoutingKey returns a kvp.Field with the messaging.rabbitmq.routing_key key and the value you provide.
	//
	// RabbitMQ message routing key.
	//
	// Type: string
	//
	// Requirement Level: Conditionally Required - If not empty.
	//
	// Examples:
	//   'myKey'
	RoutingKey func(value string) kvp.Field
}

// Attributes for RabbitMQ
var MessagingRabbitmq = messagingRabbitmq{
	RoutingKey: func(value string) kvp.Field {
		return kvp.String("messaging.rabbitmq.routing_key", value)
	},
}

// Attributes for Apache Kafka
type messagingKafka struct {
	// MessageKey returns a kvp.Field with the messaging.kafka.message_key key and the value you provide.
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
	MessageKey func(value string) kvp.Field

	// ConsumerGroup returns a kvp.Field with the messaging.kafka.consumer_group key and the value you provide.
	//
	// Name of the Kafka Consumer Group that is handling the message. Only applies to consumers, not
	// producers.
	//
	// Type: string
	//
	// Examples:
	//   'my-group'
	ConsumerGroup func(value string) kvp.Field

	// ClientId returns a kvp.Field with the messaging.kafka.client_id key and the value you provide.
	//
	// Client Id for the Consumer or Producer that is handling the message.
	//
	// Type: string
	//
	// Examples:
	//   'client-5'
	ClientId func(value string) kvp.Field

	// Partition returns a kvp.Field with the messaging.kafka.partition key and the value you provide.
	//
	// Partition the message is sent to.
	//
	// Type: int
	//
	// Examples:
	//   2
	Partition func(value int) kvp.Field

	// Tombstone returns a kvp.Field with the messaging.kafka.tombstone key and the value you provide.
	//
	// A boolean that is true if the message is a tombstone.
	//
	// Type: boolean
	//
	// Requirement Level: Conditionally Required - If value is `true`. When missing, the value is assumed to be `false`.
	Tombstone func(value bool) kvp.Field
}

// Attributes for Apache Kafka
var MessagingKafka = messagingKafka{
	MessageKey: func(value string) kvp.Field {
		return kvp.String("messaging.kafka.message_key", value)
	},

	ConsumerGroup: func(value string) kvp.Field {
		return kvp.String("messaging.kafka.consumer_group", value)
	},

	ClientId: func(value string) kvp.Field {
		return kvp.String("messaging.kafka.client_id", value)
	},

	Partition: func(value int) kvp.Field {
		return kvp.Int("messaging.kafka.partition", value)
	},

	Tombstone: func(value bool) kvp.Field {
		return kvp.Bool("messaging.kafka.tombstone", value)
	},
}

// Attributes for Apache RocketMQ
type messagingRocketmq struct {
	// Namespace returns a kvp.Field with the messaging.rocketmq.namespace key and the value you provide.
	//
	// Namespace of RocketMQ resources, resources in different namespaces are individual.
	//
	// Type: string
	//
	// Requirement Level: Required
	//
	// Examples:
	//   'myNamespace'
	Namespace func(value string) kvp.Field

	// ClientGroup returns a kvp.Field with the messaging.rocketmq.client_group key and the value you provide.
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
	ClientGroup func(value string) kvp.Field

	// ClientId returns a kvp.Field with the messaging.rocketmq.client_id key and the value you provide.
	//
	// The unique identifier for each client.
	//
	// Type: string
	//
	// Requirement Level: Required
	//
	// Examples:
	//   'myhost@8742@s8083jm'
	ClientId func(value string) kvp.Field

	// MessageType struct
	//
	// Type of message.
	//
	// Type: Enum
	MessageType struct {
		// Normal is a kvp.Field with key "messaging.rocketmq.message_type" and value "normal"
		//
		// Normal message
		Normal kvp.Field

		// Fifo is a kvp.Field with key "messaging.rocketmq.message_type" and value "fifo"
		//
		// FIFO message
		Fifo kvp.Field

		// Delay is a kvp.Field with key "messaging.rocketmq.message_type" and value "delay"
		//
		// Delay message
		Delay kvp.Field

		// Transaction is a kvp.Field with key "messaging.rocketmq.message_type" and value "transaction"
		//
		// Transaction message
		Transaction kvp.Field
	}

	// MessageTag returns a kvp.Field with the messaging.rocketmq.message_tag key and the value you provide.
	//
	// The secondary classifier of message besides topic.
	//
	// Type: string
	//
	// Examples:
	//   'tagA'
	MessageTag func(value string) kvp.Field

	// MessageKeys returns a kvp.Field with the messaging.rocketmq.message_keys key and the value you provide.
	//
	// Key(s) of message, another way to mark message besides message id.
	//
	// Type: string[]
	//
	// Examples:
	//   'keyA', 'keyB'
	MessageKeys func(value ...string) kvp.Field

	// ConsumptionModel struct
	//
	// Model of message consumption. This only applies to consumer spans.
	//
	// Type: Enum
	ConsumptionModel struct {
		// Clustering is a kvp.Field with key "messaging.rocketmq.consumption_model" and value "clustering"
		//
		// Clustering consumption model
		Clustering kvp.Field

		// Broadcasting is a kvp.Field with key "messaging.rocketmq.consumption_model" and value "broadcasting"
		//
		// Broadcasting consumption model
		Broadcasting kvp.Field
	}
}

// Attributes for Apache RocketMQ
var MessagingRocketmq = messagingRocketmq{
	Namespace: func(value string) kvp.Field {
		return kvp.String("messaging.rocketmq.namespace", value)
	},

	ClientGroup: func(value string) kvp.Field {
		return kvp.String("messaging.rocketmq.client_group", value)
	},

	ClientId: func(value string) kvp.Field {
		return kvp.String("messaging.rocketmq.client_id", value)
	},

	MessageType: struct {
		Normal      kvp.Field
		Fifo        kvp.Field
		Delay       kvp.Field
		Transaction kvp.Field
	}{
		Normal:      kvp.String("messaging.rocketmq.message_type", "normal"),
		Fifo:        kvp.String("messaging.rocketmq.message_type", "fifo"),
		Delay:       kvp.String("messaging.rocketmq.message_type", "delay"),
		Transaction: kvp.String("messaging.rocketmq.message_type", "transaction"),
	},

	MessageTag: func(value string) kvp.Field {
		return kvp.String("messaging.rocketmq.message_tag", value)
	},

	MessageKeys: func(value ...string) kvp.Field {
		return kvp.Strings("messaging.rocketmq.message_keys", value)
	},

	ConsumptionModel: struct {
		Clustering   kvp.Field
		Broadcasting kvp.Field
	}{
		Clustering:   kvp.String("messaging.rocketmq.consumption_model", "clustering"),
		Broadcasting: kvp.String("messaging.rocketmq.consumption_model", "broadcasting"),
	},
}

// This document defines semantic conventions for remote procedure calls.
type rpc struct {

	// System struct
	//
	// A string identifying the remoting system. See below for a list of well-known identifiers.
	//
	// Type: Enum
	//
	// Requirement Level: Required
	System struct {
		// Grpc is a kvp.Field with key "rpc.system" and value "grpc"
		//
		// gRPC
		Grpc kvp.Field

		// JavaRmi is a kvp.Field with key "rpc.system" and value "java_rmi"
		//
		// Java RMI
		JavaRmi kvp.Field

		// DotnetWcf is a kvp.Field with key "rpc.system" and value "dotnet_wcf"
		//
		// .NET WCF
		DotnetWcf kvp.Field

		// ApacheDubbo is a kvp.Field with key "rpc.system" and value "apache_dubbo"
		//
		// Apache Dubbo
		ApacheDubbo kvp.Field

		// CustomValue returns a kvp.Field with key "rpc.system" and the value you pass in.
		CustomValue func(value string) kvp.Field
	}

	// Service returns a kvp.Field with the rpc.service key and the value you provide.
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
	Service func(value string) kvp.Field

	// Method returns a kvp.Field with the rpc.method key and the value you provide.
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
	Method func(value string) kvp.Field
}

// This document defines semantic conventions for remote procedure calls.
var Rpc = rpc{
	System: struct {
		Grpc        kvp.Field
		JavaRmi     kvp.Field
		DotnetWcf   kvp.Field
		ApacheDubbo kvp.Field
		CustomValue func(value string) kvp.Field
	}{
		Grpc:        kvp.String("rpc.system", "grpc"),
		JavaRmi:     kvp.String("rpc.system", "java_rmi"),
		DotnetWcf:   kvp.String("rpc.system", "dotnet_wcf"),
		ApacheDubbo: kvp.String("rpc.system", "apache_dubbo"),
		CustomValue: func(value string) kvp.Field {
			return kvp.String("rpc.system", value)
		},
	},

	Service: func(value string) kvp.Field {
		return kvp.String("rpc.service", value)
	},

	Method: func(value string) kvp.Field {
		return kvp.String("rpc.method", value)
	},
}

// Semantic Convention for RPC server spans
type rpcServer struct {
}

// Semantic Convention for RPC server spans
var RpcServer = rpcServer{}

// Tech-specific attributes for gRPC.
type rpcGrpc struct {

	// StatusCode struct
	//
	// The [numeric status code](https://github.com/grpc/grpc/blob/v1.33.2/doc/statuscodes.md) of the
	// gRPC request.
	//
	// Type: Enum
	//
	// Requirement Level: Required
	StatusCode struct {
		// Ok is a kvp.Field with key "rpc.grpc.status_code" and value 0
		//
		// OK
		Ok kvp.Field

		// Cancelled is a kvp.Field with key "rpc.grpc.status_code" and value 1
		//
		// CANCELLED
		Cancelled kvp.Field

		// Unknown is a kvp.Field with key "rpc.grpc.status_code" and value 2
		//
		// UNKNOWN
		Unknown kvp.Field

		// InvalidArgument is a kvp.Field with key "rpc.grpc.status_code" and value 3
		//
		// INVALID_ARGUMENT
		InvalidArgument kvp.Field

		// DeadlineExceeded is a kvp.Field with key "rpc.grpc.status_code" and value 4
		//
		// DEADLINE_EXCEEDED
		DeadlineExceeded kvp.Field

		// NotFound is a kvp.Field with key "rpc.grpc.status_code" and value 5
		//
		// NOT_FOUND
		NotFound kvp.Field

		// AlreadyExists is a kvp.Field with key "rpc.grpc.status_code" and value 6
		//
		// ALREADY_EXISTS
		AlreadyExists kvp.Field

		// PermissionDenied is a kvp.Field with key "rpc.grpc.status_code" and value 7
		//
		// PERMISSION_DENIED
		PermissionDenied kvp.Field

		// ResourceExhausted is a kvp.Field with key "rpc.grpc.status_code" and value 8
		//
		// RESOURCE_EXHAUSTED
		ResourceExhausted kvp.Field

		// FailedPrecondition is a kvp.Field with key "rpc.grpc.status_code" and value 9
		//
		// FAILED_PRECONDITION
		FailedPrecondition kvp.Field

		// Aborted is a kvp.Field with key "rpc.grpc.status_code" and value 10
		//
		// ABORTED
		Aborted kvp.Field

		// OutOfRange is a kvp.Field with key "rpc.grpc.status_code" and value 11
		//
		// OUT_OF_RANGE
		OutOfRange kvp.Field

		// Unimplemented is a kvp.Field with key "rpc.grpc.status_code" and value 12
		//
		// UNIMPLEMENTED
		Unimplemented kvp.Field

		// Internal is a kvp.Field with key "rpc.grpc.status_code" and value 13
		//
		// INTERNAL
		Internal kvp.Field

		// Unavailable is a kvp.Field with key "rpc.grpc.status_code" and value 14
		//
		// UNAVAILABLE
		Unavailable kvp.Field

		// DataLoss is a kvp.Field with key "rpc.grpc.status_code" and value 15
		//
		// DATA_LOSS
		DataLoss kvp.Field

		// Unauthenticated is a kvp.Field with key "rpc.grpc.status_code" and value 16
		//
		// UNAUTHENTICATED
		Unauthenticated kvp.Field
	}
}

// Tech-specific attributes for gRPC.
var RpcGrpc = rpcGrpc{
	StatusCode: struct {
		Ok                 kvp.Field
		Cancelled          kvp.Field
		Unknown            kvp.Field
		InvalidArgument    kvp.Field
		DeadlineExceeded   kvp.Field
		NotFound           kvp.Field
		AlreadyExists      kvp.Field
		PermissionDenied   kvp.Field
		ResourceExhausted  kvp.Field
		FailedPrecondition kvp.Field
		Aborted            kvp.Field
		OutOfRange         kvp.Field
		Unimplemented      kvp.Field
		Internal           kvp.Field
		Unavailable        kvp.Field
		DataLoss           kvp.Field
		Unauthenticated    kvp.Field
	}{
		Ok:                 kvp.Int("rpc.grpc.status_code", 0),
		Cancelled:          kvp.Int("rpc.grpc.status_code", 1),
		Unknown:            kvp.Int("rpc.grpc.status_code", 2),
		InvalidArgument:    kvp.Int("rpc.grpc.status_code", 3),
		DeadlineExceeded:   kvp.Int("rpc.grpc.status_code", 4),
		NotFound:           kvp.Int("rpc.grpc.status_code", 5),
		AlreadyExists:      kvp.Int("rpc.grpc.status_code", 6),
		PermissionDenied:   kvp.Int("rpc.grpc.status_code", 7),
		ResourceExhausted:  kvp.Int("rpc.grpc.status_code", 8),
		FailedPrecondition: kvp.Int("rpc.grpc.status_code", 9),
		Aborted:            kvp.Int("rpc.grpc.status_code", 10),
		OutOfRange:         kvp.Int("rpc.grpc.status_code", 11),
		Unimplemented:      kvp.Int("rpc.grpc.status_code", 12),
		Internal:           kvp.Int("rpc.grpc.status_code", 13),
		Unavailable:        kvp.Int("rpc.grpc.status_code", 14),
		DataLoss:           kvp.Int("rpc.grpc.status_code", 15),
		Unauthenticated:    kvp.Int("rpc.grpc.status_code", 16),
	},
}

// Tech-specific attributes for [JSON RPC](https://www.jsonrpc.org/).
type rpcJsonrpc struct {
	// Version returns a kvp.Field with the rpc.jsonrpc.version key and the value you provide.
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
	Version func(value string) kvp.Field

	// RequestId returns a kvp.Field with the rpc.jsonrpc.request_id key and the value you provide.
	//
	// `id` property of request or response. Since protocol allows id to be int, string, `null` or
	// missing (for notifications), value is expected to be cast to string for simplicity. Use empty
	// string in case of `null` value. Omit entirely if this is a notification.
	//
	// Type: string
	//
	// Examples:
	//   '10', 'request-7', ''
	RequestId func(value string) kvp.Field

	// ErrorCode returns a kvp.Field with the rpc.jsonrpc.error_code key and the value you provide.
	//
	// `error.code` property of response if it is an error response.
	//
	// Type: int
	//
	// Requirement Level: Conditionally Required - If response is not successful.
	//
	// Examples:
	//   -32700, 100
	ErrorCode func(value int) kvp.Field

	// ErrorMessage returns a kvp.Field with the rpc.jsonrpc.error_message key and the value you provide.
	//
	// `error.message` property of response if it is an error response.
	//
	// Type: string
	//
	// Examples:
	//   'Parse error', 'User already exists'
	ErrorMessage func(value string) kvp.Field
}

// Tech-specific attributes for [JSON RPC](https://www.jsonrpc.org/).
var RpcJsonrpc = rpcJsonrpc{
	Version: func(value string) kvp.Field {
		return kvp.String("rpc.jsonrpc.version", value)
	},

	RequestId: func(value string) kvp.Field {
		return kvp.String("rpc.jsonrpc.request_id", value)
	},

	ErrorCode: func(value int) kvp.Field {
		return kvp.Int("rpc.jsonrpc.error_code", value)
	},

	ErrorMessage: func(value string) kvp.Field {
		return kvp.String("rpc.jsonrpc.error_message", value)
	},
}

// RPC received/sent message.
type rpcMessage struct {

	// Type struct
	//
	// Whether this is a received or sent message.
	//
	// Type: Enum
	Type struct {
		// Sent is a kvp.Field with key "message.type" and value "SENT"
		//
		// sent
		Sent kvp.Field

		// Received is a kvp.Field with key "message.type" and value "RECEIVED"
		//
		// received
		Received kvp.Field
	}

	// Id returns a kvp.Field with the message.id key and the value you provide.
	//
	// MUST be calculated as two different counters starting from `1` one for sent messages and one for
	// received message.
	//
	// Type: int
	//
	// Note:
	// This way we guarantee that the values will be consistent between different implementations.
	Id func(value int) kvp.Field

	// CompressedSize returns a kvp.Field with the message.compressed_size key and the value you provide.
	//
	// Compressed size of the message in bytes.
	//
	// Type: int
	CompressedSize func(value int) kvp.Field

	// UncompressedSize returns a kvp.Field with the message.uncompressed_size key and the value you provide.
	//
	// Uncompressed size of the message in bytes.
	//
	// Type: int
	UncompressedSize func(value int) kvp.Field
}

// RPC received/sent message.
var RpcMessage = rpcMessage{
	Type: struct {
		Sent     kvp.Field
		Received kvp.Field
	}{
		Sent:     kvp.String("message.type", "SENT"),
		Received: kvp.String("message.type", "RECEIVED"),
	},

	Id: func(value int) kvp.Field {
		return kvp.Int("message.id", value)
	},

	CompressedSize: func(value int) kvp.Field {
		return kvp.Int("message.compressed_size", value)
	},

	UncompressedSize: func(value int) kvp.Field {
		return kvp.Int("message.uncompressed_size", value)
	},
}
