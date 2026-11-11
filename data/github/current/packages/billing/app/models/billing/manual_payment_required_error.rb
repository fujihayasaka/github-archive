# typed: strict
# frozen_string_literal: true

module Billing
  # Raised when an advance payment for an upgrade is declined for a customer that must complete
  # payments manually (e.g. India RBI). Callers should redirect the customer to the manual payments
  # page for the carried `invoice_id`, where they can authenticate and complete the payment; once it
  # succeeds the upgrade is finalized by re-issuing the original request.
  #
  # This is intentionally product-agnostic: any product that collects an advance payment on upgrade
  # surfaces this same error, and the manual payments page finalizes the upgrade via a
  # Billing::PendingManualPaymentUpgrade supplied by the product.
  class ManualPaymentRequiredError < StandardError
    DEFAULT_MESSAGE = T.let("A manual payment is required to complete this transaction.", String)

    # The Zuora invoice id the customer must pay manually to complete the transaction.
    sig { returns(T.nilable(String)) }
    attr_reader :invoice_id

    sig { params(invoice_id: T.nilable(String), message: String).void }
    def initialize(invoice_id: nil, message: DEFAULT_MESSAGE)
      @invoice_id = invoice_id
      super(message)
    end
  end
end
