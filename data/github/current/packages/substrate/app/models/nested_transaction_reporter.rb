# typed: true
# frozen_string_literal: true

class NestedTransactionReporter
  cattr_accessor :raise_on_cross_cluster_nested_transactions, default: GitHub::AppEnvironment.test?

  def initialize(transaction_state, transaction_time, clusters_with_open_transactions)
    @transaction_state = transaction_state
    @transaction_time = transaction_time
    @clusters_with_open_transactions = clusters_with_open_transactions
  end

  def call
    return unless transactions_nested_across_clusters?

    if raise_on_cross_cluster_nested_transactions
      raise_cross_cluster_nested_transaction_error
    else
      return unless GitHub.datadog_enabled?
      report_transactions_nested_across_clusters
    end
  end

  private

  attr_reader :transaction_state, :transaction_time, :clusters_with_open_transactions

  def transactions_nested_across_clusters?
    cluster_count > 1
  end

  def raise_cross_cluster_nested_transaction_error
    unless skip_raise?
      raise MysqlTransactionReporter::CrossClusterNestedTransaction.new(clusters_with_open_transactions)
    end
  end

  def skip_raise?
    return true unless raise_on_cross_cluster_nested_transactions

    @ignore_pattern ||= Regexp.union(
      Rails.application.config_for(:transaction_tracking).dig(:nested_across_clusters, :ignore)
    )

    caller.any? { |line| line.match?(@ignore_pattern) }
  end

  def report_transactions_nested_across_clusters
    cross_cluster_tags = ["cluster_count:#{cluster_count}"]
    GitHub.dogstats.increment("rpc.mysql.transaction.nested_cross_cluster", tags: cross_cluster_tags)

    failbot_report if failbot_report?
  end

  def cluster_count
    clusters_with_open_transactions.length
  end

  TWO_CLUSTER_SAMPLE_RATE = 0.01

  def failbot_report?
    if cluster_count == 2
      rand < TWO_CLUSTER_SAMPLE_RATE
    else
      true
    end
  end

  FAILBOT_APP = "github-slow-transaction"

  def failbot_report
    error = MysqlTransactionReporter::CrossClusterNestedTransaction.new(clusters_with_open_transactions)
    error.set_backtrace(caller)
    Failbot.report!(error, app: FAILBOT_APP, transaction_time_ms: transaction_time.duration)
  end
end
