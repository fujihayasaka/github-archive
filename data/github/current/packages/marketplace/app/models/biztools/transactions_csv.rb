# typed: true
# frozen_string_literal: true

module Biztools
  module TransactionsCsv
    def generate_csv(transactions)
      CSV.generate do |csv|
        csv << csv_headers
        transactions.each { |txn| csv << csv_values(txn) }
      end
    end

    def csv_headers
      %w[
        created_at
        user_login
        user_id
        user_type
        amount
        status
        transaction_type
        transaction_id
        service_ends_at
        settlement_batch_id
      ]
    end

    def csv_values(transaction)
      [
        transaction.created_at,
        transaction.user_login,
        transaction.user_id,
        transaction.user_type,
        transaction.amount,
        transaction.last_status,
        transaction.transaction_type,
        transaction.transaction_id,
        transaction.service_ends_at,
        transaction.settlement_batch_id,
      ]
    end
  end
end
