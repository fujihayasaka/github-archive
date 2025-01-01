# typed: true
# frozen_string_literal: true

class SponsorsProcessRefundJob < ApplicationJob
  extend T::Sig
  retry_on_dirty_exit

  queue_as :sponsors_process_refund

  sig do
    params(
      refund_transaction: Billing::BillingTransaction,
      sale_transaction: Billing::BillingTransaction,
    ).void
  end
  def perform(refund_transaction:, sale_transaction:)
    # TODO: Implement this method once it's sponsors-owned :-)
  end
end
