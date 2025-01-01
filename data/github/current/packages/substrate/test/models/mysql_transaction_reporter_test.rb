# typed: true
# frozen_string_literal: true

require "test_helper"

class MysqlTransactionReporterTest < GitHub::TestCase
  setup do
    GitHub.stubs(:datadog_enabled?).returns(true)
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
  end

  test "#call collects timing stats", skip_enterprise: true do
    transaction_time = TimeSpan.
      new(Time.new(2018, 10, 31, 1, 4), Time.new(2018, 10, 31, 1, 5))

    MysqlTransactionReporter.new(:commit, transaction_time, ["Mysql1"]).call

    assert_equal [60000], GitHub.dogstats.distributions("rpc.mysql.transaction.time", tags: ["source:unknown", "transaction_state:commit"])&.map(&:value)
  end

  test "#call sends slow transactions to failbot", skip_enterprise: true do
    fast_transaction_time = TimeSpan.
      new(Time.new(2018, 10, 31, 1, 5, 0, 0), Time.new(2018, 10, 31, 1, 5, 0, 1))
    slow_transaction_time = TimeSpan.
      new(Time.new(2018, 10, 31, 1, 5, 0), Time.new(2018, 10, 31, 1, 5, 30))

    refute_error_reported do
      MysqlTransactionReporter.new(:commit, fast_transaction_time, ["Mysql1"]).call
    end

    assert_error_reported_with_message(MysqlTransactionReporter::SlowTransaction, "Transaction took 30 seconds.") do
      MysqlTransactionReporter.new(:commit, slow_transaction_time, ["Mysql1"]).call
    end
  end

  test "#call collects timing stats collected from a job", skip_enterprise: true do
    transaction_time = TimeSpan.
      new(Time.new(2018, 10, 31, 1, 4), Time.new(2018, 10, 31, 1, 5))

    GitHub.context.push(job: "MyJob")

    MysqlTransactionReporter.new(:commit, transaction_time, ["Mysql1"]).call

    assert_equal [60000], GitHub.dogstats.distributions("rpc.mysql.transaction.time", tags: ["source:MyJob", "transaction_state:commit"])&.map(&:value)
  end

  test "#call collects timing stats collected from code outside of the context of a job", skip_enterprise: true do
    transaction_time = TimeSpan.
      new(Time.new(2018, 10, 31, 1, 4), Time.new(2018, 10, 31, 1, 5))

    GitHub.context.push(from: "random-location", job: "MyJob")

    MysqlTransactionReporter.new(:commit, transaction_time, ["Mysql1"]).call

    assert_equal [60000], GitHub.dogstats.distributions("rpc.mysql.transaction.time", tags: ["source:random-location", "transaction_state:commit"])&.map(&:value)

    assert_empty GitHub.dogstats.distributions("rpc.mysql.transaction.time", tags: ["source:MyJob"])
  end
end
