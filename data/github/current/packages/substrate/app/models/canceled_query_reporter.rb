# typed: true
# frozen_string_literal: true

# The CanceledQueryReporter class is responsible for reporting queries that are canceled due to platform-set
# server-side execution time limits. The format of the log message is designed to be compatible with github/quoroner
# logs. github/mysql-database-usage inspects logs in the prod-quoroner index and tracks problematic queries.
#
# See https://github.com/github/mysql-database-usage for more information.
class CanceledQueryReporter
  include GitHub::Memoizer

  def initialize(query:, connection:)
    @connection = connection
    # start/finish are floats due to monotonic subscription,
    # so we get an approximate timestamp by taking the current time
    # This is a MysqlInstrumenter::Query
    @query = query
    @digester = QueryDigester.new(query, @connection)
  end

  def self.call(query:, connection:)
    reporter = new(query:, connection:)
    reporter.report
  end

  def report
    # ignore connections that do not have a max execution time set
    return if connection_max_execution_time.zero?
    # ignore queries that explicitly set a max execution time if it is less than the cluster max
    return if @digester.max_execution_time && @digester.max_execution_time.to_i < connection_max_execution_time
    # ignore queries that are attempting to generate a statement digest, as this could result in an infinite loop
    return if @digester.digest_query?

    # Get SQL comment tags from the query string
    all_tags = @query.sql_comment_tags || {}

    GlobalInstrumenter.instrument("mysql.query.canceled", kusto_tags(all_tags))

    GitHub.logger.info("canceled query", **splunk_tags(all_tags))
  end

  private

  def splunk_tags(all_tags)
    {
      "splunk_sourcetype": "github-canceled-query-reporter",
      "splunk_index": "prod-quoroner",
      "mysql_digest": @digester.digest || "unknown",
      "application": "github",
      "route": all_tags[:route] || true,
      "job": all_tags[:job] || true,
      "msg": "canceled query",
      "catalog_service": all_tags[:catalog_service] || nil,
      "query_trimmed": @query.sql.length == @digester.truncate.length,
      "query_length_untrimmed": @query.sql.length,
      "job_id": all_tags[:job_id] || true,
      "query_length_trimmed": @digester.truncate.length,
      "db_cluster": cluster_name,
      "db_hostname": "NA",
      "request_id": all_tags[:request_id] || true,
      "reason": "Exceeds MAX_EXECUTION_TIME",
      "user": sql_user,
      "db": production_schema_name,
      "time": @query.duration.floor,
      "query": @digester.truncate,
    }
  end

  def kusto_tags(all_tags)
    {
      "query": @digester.truncate,
      "digest": @digester.digest || "unknown",
      "user": sql_user,
      "schema": production_schema_name,
      "cluster_name": cluster_name,
      "time": @query.duration.floor,
      "app": all_tags[:app] || nil,
      "catalog_service": all_tags[:catalog_service] || nil,
      "deployed_to": all_tags[:deployed_to] || nil,
      "category": all_tags[:category] || nil,
      "job": all_tags[:job] || nil,
      "job_id": all_tags[:job_id] || nil,
      "request_id": all_tags[:request_id] || Rack::RequestId.current,
      "route": all_tags[:route] || nil,
      "package": all_tags[:package] || nil,
      "name": all_tags[:name] || nil,
      "server": all_tags[:server] || nil,
      "length_trimmed": @digester.truncate.length,
      "length_untrimmed": @query.sql.length,
      "type": "canceled query",
      "query_trimmed": @digester.truncate,
    }
  end

  def sql_user
    @connection.raw_connection.connection_options[:username]
  end

  def connection_class
    @connection.connection_class
  end

  def connection_max_execution_time
    # Get the max_execution_time from the database connection configuration (mainly non-vitess clusters)
    db_max_time = connection_class.connection_db_config.configuration_hash[:variables]["max_execution_time"] || 0

    # Get the max_execution_time from the connection class (mainly vitess clusters)
    # These clusters include the GitHub::MaxExecutionTime module, which exposes a
    # class method `max_execution_time` (backed by feature flags and constants)
    # that is used to set the max execution time for queries.
    class_max_time = if connection_class.respond_to?(:max_execution_time)
      connection_class.max_execution_time
    else
      0
    end
    [db_max_time.to_i, class_max_time.to_i].max
  end

  def production_schema_name
    connection_class.production_schema_name
  end

  def cluster_name
    connection_class.cluster_name.to_s
  end
end
