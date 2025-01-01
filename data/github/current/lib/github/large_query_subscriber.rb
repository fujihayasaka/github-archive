# typed: true
# frozen_string_literal: true

require "github/sql/digester"

# Listens for SQL statements over a configured size and reports them to failbot.
#
# Very large SQL text can cause the MySQL server to disconnect while receiving
# it, so we should try to keep the size managable.  If your code is flagged by
# this, consider batching (for example using GitHub::BatchedScope) or other
# alternatives to passing very large lists of ids in a single query.
class GitHub::LargeQuerySubscriber
  FAILBOT_APP = "github-large-queries"
  INSTRUMENTATION_SAMPLE_RATE = 0.0001
  INSTRUMENTATION_TIMING_METRIC = "query_subscriber.large_sql.instrument_time"
  QUERY_TIMING_METRIC = "query_subscriber.large_sql.execution_time"
  COUNT_METRIC = "query_subscriber.large_sql.count"

  def initialize(threshold:, truncation_size: 1000)
    @threshold = threshold
    @truncation_size = truncation_size
    @truncation_midpoint = truncation_size / 2
  end

  def call(event, start, ending, notifier_id, payload)
    GitHub.dogstats.time(INSTRUMENTATION_TIMING_METRIC, sample_rate: INSTRUMENTATION_SAMPLE_RATE) do
      sql = payload[:sql].to_s
      if sql.bytesize > @threshold
        query_duration = TimeSpan.new(start, ending).duration
        notify_failbot(payload, query_duration)
        notify_statsd(payload, query_duration)
      end
    end
  end

  def notify_failbot(payload, query_duration)
    sql = payload[:sql].to_s
    error = TooLarge.new("SQL has excessive size. Too many ids listed?", payload[:connection]&.pool)
    stack = caller
    frame = Rollup.first_significant_frame(stack)
    error.set_backtrace(stack)

    common_sql = GitHub::SQL::Digester.digest_sql(sql)
    ins = (common_sql.include?("IN ?") && sql.match(/IN\s*\(([^\)]*)\)/)&.captures&.first&.count(",") || -1) + 1
    truncated_sql = common_sql.truncate(@truncation_size, omission: "...#{common_sql.last(@truncation_midpoint)}") # elide middle
    rollup = Digest::SHA256.hexdigest(common_sql)

    Failbot.report!(error, app: FAILBOT_APP, sql_size: sql.bytesize, sql_truncated: truncated_sql, sql_in_values_count: ins, rollup: rollup, query_duration_ms: query_duration)
  end

  def notify_statsd(payload, query_duration)
    tags = ["error:#{!!payload[:exception]}"]
    GitHub.dogstats.timing(QUERY_TIMING_METRIC, query_duration, tags: tags)
    GitHub.dogstats.increment(COUNT_METRIC, tags: tags)
  end

  class TooLarge < StandardError
    attr_reader :connection_pool

    def initialize(message, connection_pool)
      super(message)

      @connection_pool = connection_pool
    end

  end
end
