# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class UpdateBillingTransactionStatusJob < BillingJob
  def perform(transaction)
    with_write { transaction.update_status_from_processor }
  end
end
