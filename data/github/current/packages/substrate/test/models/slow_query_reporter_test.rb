# typed: true
# frozen_string_literal: true

require "connection_info"
require "test_helper"

class SlowQueryReporterTest < GitHub::TestCase
  def connection_info
    ConnectionInfo.new(host: nil, connection_class: ActiveRecord::Base)
  end

  if GitHub.enterprise?
    test "#report includes slow queries in the slow query bucket" do
      reporter = SlowQueryReporter.new(
        "select * from foo",
        SlowQueryReporter::SLOW_QUERY_ALERT_THRESHOLD + 1,
        connection_info,
      )

      reporter.report

      buckets = Failbot.reports.last(2).map { |report| report["app"] }
      assert_equal %w[github-slow-query github-slow-query-alert], buckets
    end

    test "#report times slow queries" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      reporter = SlowQueryReporter.new(
        "select * from foo",
        SlowQueryReporter::SLOW_QUERY_ALERT_THRESHOLD + 1,
        connection_info,
      )

      reporter.report

      assert_equal 1, GitHub.dogstats.timings("rpc.mysql.slow_query.time").length
    end
  end

  test "#report times and increments killed slow queries" do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

    reporter = SlowQueryReporter.new(
      "select * from foo",
      SlowQueryReporter::SLOW_QUERY_KILL_THRESHOLD,
      connection_info,
    )

    reporter.report

    assert_equal 1, GitHub.dogstats.timings("rpc.mysql.slow_query.time").length
    assert_equal 1, GitHub.dogstats.increments("rpc.mysql.slow_query.kill_count").length
  end

  test "#report doesn't report on fast queries" do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

    reporter = SlowQueryReporter.new(
      "select * from foo",
      SlowQueryReporter::SLOW_QUERY_ALERT_THRESHOLD - 1,
      connection_info,
    )

    reporter.report

    assert_empty GitHub.dogstats.timings("rpc.mysql.slow_query.time")
    assert_empty GitHub.dogstats.increments("rpc.mysql.slow_query.kill_count")
  end

  test "#report doesn't report when skipping is enabled" do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

    SlowQueryLogger.disabled do
      reporter = SlowQueryReporter.new(
        "select * from foo",
        SlowQueryReporter::SLOW_QUERY_ALERT_THRESHOLD + 1,
        connection_info,
      )

      reporter.report
    end

    assert_empty GitHub.dogstats.timings("rpc.mysql.slow_query.time")
    assert_empty GitHub.dogstats.increments("rpc.mysql.slow_query.kill_count")
  end
end
