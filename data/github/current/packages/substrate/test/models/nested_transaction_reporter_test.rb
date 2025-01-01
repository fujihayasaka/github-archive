# typed: true
# frozen_string_literal: true

require "test_helper"

class NestedTransactionReporterTest < GitHub::TestCase
  setup do
    GitHub.stubs(:datadog_enabled?).returns(true)
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

    @raise_was = NestedTransactionReporter.raise_on_cross_cluster_nested_transactions
    NestedTransactionReporter.raise_on_cross_cluster_nested_transactions = false
  end

  teardown do
    NestedTransactionReporter.raise_on_cross_cluster_nested_transactions = @raise_was
  end

  test "#call collects nested_cross_cluster stats for multiple clusters" do
    transaction_time = TimeSpan.
      new(Time.new(2018, 10, 31, 1, 4), Time.new(2018, 10, 31, 1, 5))

    NestedTransactionReporter.new(:commit, transaction_time, %w[Mysql1 Mysql2]).call
    NestedTransactionReporter.new(:commit, transaction_time, %w[Mysql1 Mysql2 Ballast]).call

    increments = GitHub.dogstats.increments("rpc.mysql.transaction.nested_cross_cluster")
    assert_equal [["cluster_count:2"], ["cluster_count:3"]], increments&.map { |stat| stat.tags.to_a }
  end

  test "#call sends cross cluster transactions to failbot" do
    NestedTransactionReporter.any_instance.stubs(:rand).returns(0)
    transaction_time = TimeSpan.
      new(Time.new(2018, 10, 31, 1, 4), Time.new(2018, 10, 31, 1, 5))
    clusters = %w[Mysql1 Mysql2]

    assert_error_reported_with_message(
      MysqlTransactionReporter::CrossClusterNestedTransaction,
      "Transactions nested across clusters: Mysql1, Mysql2. This is an availability risk and does not provide transactional guarantees across clusters."
    ) do
      NestedTransactionReporter.new(:commit, transaction_time, clusters).call
    end
    assert_equal 60_000, Failbot.reports.last["transaction_time_ms"]
  end

  test "#call does not report non-nested transactions", skip_enterprise: true do
    transaction_time = TimeSpan.
      new(Time.new(2018, 10, 31, 1, 4), Time.new(2018, 10, 31, 1, 5))

    NestedTransactionReporter.new(:commit, transaction_time, ["Mysql1"]).call

    assert_empty GitHub.dogstats.increments("rpc.mysql.transaction.nested_cross_cluster")
  end
end

class NestedTransactionReporterRaisesTest < GitHub::TestCase
  test "#call raises when transactions are nested across more clusters than allowed clusters" do
    transaction_time = TimeSpan.
      new(Time.new(2018, 10, 31, 1, 4), Time.new(2018, 10, 31, 1, 5))
    clusters = %w[Mysql1 Mysql2 Repositories]

    assert_raises MysqlTransactionReporter::CrossClusterNestedTransaction do
      NestedTransactionReporter.new(:commit, transaction_time, clusters).call
    end
  end

  test "#call doesn't raise for single cluster transactions" do
    transaction_time = TimeSpan.
      new(Time.new(2018, 10, 31, 1, 4), Time.new(2018, 10, 31, 1, 5))
    clusters = ["Mysql1"]

    assert_nothing_raised { NestedTransactionReporter.new(:commit, transaction_time, clusters).call }
  end
end
