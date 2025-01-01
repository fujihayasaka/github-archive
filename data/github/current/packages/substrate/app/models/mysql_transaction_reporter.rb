# typed: true
# frozen_string_literal: true

class MysqlTransactionReporter
  extend T::Helpers

  def initialize(transaction_state, transaction_time, clusters_with_open_transactions)
    @transaction_state = transaction_state
    @transaction_time = transaction_time
    @clusters_with_open_transactions = clusters_with_open_transactions
  end

  def call
    return unless GitHub.datadog_enabled?

    report_transaction_time
    report_slow_transaction if report_slow_transaction?
  end

  private

  def report_transaction_time
    source = GitHub.context[:from] || GitHub.context[:job] || "unknown"
    tags = ["source:#{source}"]
    tags << "transaction_state:#{transaction_state}" unless transaction_state.nil?

    GitHub.dogstats.distribution("rpc.mysql.transaction.time", transaction_time.duration, tags: tags)
  end

  def report_slow_transaction?
    transaction_time.duration_seconds > 15.seconds
  end

  def report_slow_transaction
    error = SlowTransaction.new(transaction_time.duration_seconds.round)
    error.set_backtrace(caller)
    Failbot.report!(error, app: FAILBOT_APP)
  end

  FAILBOT_APP = "github-slow-transaction"

  class SlowTransaction < StandardError
    def initialize(seconds)
      super("Transaction took #{seconds} seconds.")
    end
  end

  # Leaving in MysqlTransactionReporter to avoid changing rollups for this
  # error for now. We can probably move this into NestedTransactinoReporter once
  # https://github.com/github/fanout/issues/1121 is complete.
  #
  # Inheriting from Exception is generally NOT the right thing to do, but
  # this error is only raised in test, and we don't want it to get rescued since
  # that leads to confusing test failures.
  class CrossClusterNestedTransaction < Exception
    def initialize(clusters)
      super("Transactions nested across clusters: #{clusters.join(", ")}. This is an availability risk and does not provide transactional guarantees across clusters.")
    end
  end

  attr_reader :transaction_state, :transaction_time, :clusters_with_open_transactions
end
