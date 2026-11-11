# typed: true
# frozen_string_literal: true

require "github/sql/digester"

class SlowQueryReporter
  SLOW_QUERY_ALERT_THRESHOLD = if GitHub.enterprise?
    5.0
  else
    2.0
  end

  SLOW_QUERY_KILL_THRESHOLD = 20.0

  attr_reader :sql, :duration_seconds, :connection_info

  def initialize(sql, duration_seconds, connection_info)
    @sql = sql
    @duration_seconds = duration_seconds
    @connection_info = connection_info
  end

  def report
    return unless SlowQueryReporter.report_slow_query?(@duration_seconds)
    return if SlowQueryLogger.should_skip?(trace)
    report_to_failbot
    report_to_dogstats
  end

  def self.report_slow_query?(duration_seconds)
    GitHub.enterprise? && duration_seconds >= SLOW_QUERY_ALERT_THRESHOLD
  end

  private

  def report_to_failbot
    sql = GitHub::SQL::Digester.digest_sql(self.sql)

    error = SlowQueryLogger::SlowQuery.new(sql, duration_seconds)
    error.set_backtrace(trace)

    buckets = %w[github-slow-query github-slow-query-alert]

    buckets.each do |bucket|
      Failbot.report!(
        error,
        "app" => bucket,
        "db.statement" => sql,
        "rollup" => Digest::SHA256.hexdigest(sql),
        "gh.db.connection_url" => connection_info.url,
        "gh.db.connection_host" => connection_info.config_host,
        "#gh.db.connection_role" => connection_info.connection_role.to_s, # send as a tag
      )
    end
  end

  def report_to_dogstats
    GitHub.dogstats.timing("rpc.mysql.slow_query.time", duration_seconds)

    if duration_seconds >= SLOW_QUERY_KILL_THRESHOLD
      GitHub.dogstats.increment("rpc.mysql.slow_query.kill_count")
    end
  end

  def trace
    @trace ||= caller.dup
  end
end
