# typed: true
# frozen_string_literal: true

# The CanceledQueryReporter class is responsible for reporting queries that are canceled due to platform-set
# server-side execution time limits. The format of the log message is designed to be compatible with github/quoroner
# logs. github/mysql-database-usage inspects logs in the prod-quoroner index and tracks problematic queries.
#
# See https://github.com/github/mysql-database-usage for more information.
class CanceledQueryReporter
  include GitHub::Memoizer

  PLATFORM_MAX_EXECUTION_TIME = 5000 # in milliseconds

  def initialize(query:, connection:, start:, finish:)
    @connection = connection
    @time_span = GitHub::TimeSpan.new(start, finish)
    # start/finish are floats due to monotonic subscription,
    # so we get an approximate timestamp by taking the current time
    @timestamp = Time.now
    @digester = QueryDigester.new(query, @connection)
  end

  def self.call(query:, connection:, start:, finish:)
    reporter = new(query:, connection:, start:, finish:)
    reporter.report
  end

  def report
    # ignore queries that explicitly set a max execution time if it is less than the platform max
    return if @digester.max_execution_time && @digester.max_execution_time.to_i < PLATFORM_MAX_EXECUTION_TIME
    # ignore queries that are attempting to generate a statement digest, as this could result in an infinite loop
    return if @digester.digest_query?

    GitHub.logger.info("canceled query", {
      "query": @digester.truncate,
      "mysql_digest": @digester.digest || "unknown",
      "user": sql_user,
      "db": production_schema_name,
      "db_cluster": cluster_name,
      "timestamp": timestamp,
      "time": @time_span.duration_seconds.floor.to_s,
      "time_ms": @time_span.duration.floor.to_s,
      "splunk_sourcetype": "github-canceled-query-reporter",
      "splunk_index": "prod-quoroner",
    })
  end

  private

  def sql_user
    @connection.raw_connection.connection_options[:username]
  end

  def connection_class
    @connection.connection_class
  end

  def production_schema_name
    connection_class.production_schema_name
  end

  def cluster_name
    connection_class.cluster_name.to_s
  end

  def timestamp
    # Quoroner logs currently use a naive US/Pacific time, so we emulate that here.
    @timestamp.in_time_zone("US/Pacific").strftime("%Y-%m-%dT%H:%M:%S")
  end
end
