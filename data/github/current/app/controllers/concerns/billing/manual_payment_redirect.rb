# typed: strict
# frozen_string_literal: true

module Billing
  # Redirects RBI-style manual-payment upgrades to the manual payments page and back. Products supply
  # a Billing::PendingManualPaymentUpgrade describing how to finalize; this concern handles the rest.
  module ManualPaymentRedirect
    extend ActiveSupport::Concern
    extend T::Helpers

    requires_ancestor { ApplicationController }

    # Marks a re-POST as a finalization attempt so the create action retries activation instead of
    # looping back to the payment page when payment isn't confirmed yet.
    FINALIZATION_PARAM = "manual_payment_finalization"

    # Flags the checkout page (via query param) to show the "still processing, activate again" banner
    # after the customer is sent back because their manual payment couldn't be confirmed in time.
    PAYMENT_PROCESSING_PARAM = "payment_processing"

    # Shown when a finalization re-POST can't complete the upgrade (payment not yet confirmed).
    FINALIZATION_RETRY_MESSAGE = "Thanks for your payment. It may already be complete, but can take " \
      "a few moments to process. Please select \"Activate now\" again to finish setting up your " \
      "subscription. If your payment has already gone through, you won't be charged again."

    # Redirects to the manual payments page when `error` requires manual payment (India RBI). Returns
    # true if redirected, false otherwise.
    #
    # `pending_upgrade`: stashed so the page can finalize a deferred upgrade after payment succeeds.
    # `require_pending_upgrade`: when true (default), opt out if `pending_upgrade` is nil. Pass false for
    # flows with nothing to finalize (e.g. pay-as-you-go usage charges).
    sig do
      params(
        error: T.untyped,
        target: ::Billing::Types::Account,
        pending_upgrade: T.nilable(::Billing::PendingManualPaymentUpgrade),
        require_pending_upgrade: T::Boolean,
      ).returns(T::Boolean)
    end
    def redirect_to_manual_payment_if_required(error, target:, pending_upgrade: nil, require_pending_upgrade: true)
      return false unless error.is_a?(::Billing::ManualPaymentRequiredError)
      return false if require_pending_upgrade && pending_upgrade.nil?

      invoice_id = error.invoice_id
      return false if invoice_id.blank?

      if pending_upgrade
        ::Billing::PendingManualPaymentUpgrade.store(target: target, invoice_id: invoice_id, pending_upgrade: pending_upgrade)
      end
      redirect_to manual_payment_path_for(target, invoice_id: invoice_id)
      true
    end

    # True when the current request is a finalization re-POST.
    sig { returns(T::Boolean) }
    def manual_payment_finalization?
      params[FINALIZATION_PARAM].present?
    end

    # True when the advance payment for `invoice_id` has been recorded as collected (its Zuora payment
    # processed). Used to gate the reassuring FINALIZATION_RETRY_MESSAGE so we only tell customers their
    # payment is on its way when we can confirm it actually went through. See
    # Billing::AdvancePayment.collected_payments.
    sig { params(target: ::Billing::Types::Account, invoice_id: T.nilable(String)).returns(T::Boolean) }
    def manual_payment_collected?(target:, invoice_id:)
      return false if invoice_id.blank?

      customer = target.customer
      return false if customer.nil?

      ::Billing::AdvancePayment.collected_payments(customer: customer).any? { |payment| payment.invoice_id == invoice_id }
    end

    # The pending upgrade stashed for `target` + `invoice_id`, or nil when none is pending.
    sig { params(target: ::Billing::Types::Account, invoice_id: T.nilable(String)).returns(T.nilable(::Billing::PendingManualPaymentUpgrade)) }
    def pending_manual_payment_upgrade(target:, invoice_id:)
      ::Billing::PendingManualPaymentUpgrade.fetch(target: target, invoice_id: invoice_id)
    end

    private

    sig { params(target: ::Billing::Types::Account, invoice_id: String).returns(String) }
    def manual_payment_path_for(target, invoice_id:)
      if target.organization?
        org_bill_pay_new_path(organization_id: target.display_login, invoice_id: invoice_id)
      else
        bill_pay_new_path(invoice_id: invoice_id)
      end
    end
  end
end
