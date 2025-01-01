# typed: true
# frozen_string_literal: true

class UpdateBillingTransactionStatusJob < BillingJob
  queue_as :billing

  def perform(transaction)
    with_write { transaction.update_status_from_processor }
  end
end
