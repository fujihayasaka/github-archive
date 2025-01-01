# typed: true
# frozen_string_literal: true

module Biztools
  class YearlyRefundsReport
    include Biztools::TransactionsCsv

    def initialize(year, month)
      @start_date = Date.new(year, month, 1)
    end

    def filename
      "yearly-refunds-#{start_date.strftime "%Y-%m"}.csv"
    end

    def generate
      conditions = [
        "transaction_type = ? and created_at >= ? and created_at < ?",
        "refund",
        start_date,
        start_date + 1.month,
      ]
      refunds = Billing::BillingTransaction.where(conditions).to_a

      original_ids = refunds.map(&:sale_transaction_id)
      txns = Billing::BillingTransaction.yearly.where(transaction_id: original_ids).to_a
      txn_ids = txns.map(&:transaction_id)
      refunds.select! { |refund| txn_ids.include? refund.sale_transaction_id }

      generate_csv(refunds)
    end

    private

    attr_reader :start_date
  end
end
