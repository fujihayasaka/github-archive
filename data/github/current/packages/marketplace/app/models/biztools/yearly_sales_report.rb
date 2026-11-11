# typed: true
# frozen_string_literal: true

module Biztools
  class YearlySalesReport
    include Biztools::TransactionsCsv

    def initialize(year, month)
      @start_date = Date.new(year, month, 1)
    end

    def filename
      "yearly-transactions-#{start_date.strftime "%Y-%m"}.csv"
    end

    def generate
      conditions = [
        "created_at >= ? and created_at < ?",
        start_date,
        start_date + 1.month,
      ]
      txns = Billing::BillingTransaction.yearly.sales.where(conditions).to_a

      txns.select! { |txn| txn.settled? }

      generate_csv(txns)
    end

    private

    attr_reader :start_date
  end
end
