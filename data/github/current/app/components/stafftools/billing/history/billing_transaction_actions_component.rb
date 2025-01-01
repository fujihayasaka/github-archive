# typed: strict
# frozen_string_literal: true

module Stafftools::Billing::History
  class BillingTransactionActionsComponent < ApplicationComponent
    include Stafftools::BillingHelper

    sig { returns(Stafftools::Billing::PaymentRecord) }
    attr_reader :payment

    sig { returns(T.nilable(T.any(Billing::Types::Account, Billing::DeadUser))) }
    attr_reader :target

    sig { params(payment: Stafftools::Billing::PaymentRecord).void }
    def initialize(payment:)
      @payment = payment
      @target = T.let(payment.billable_entity, T.nilable(T.any(Billing::Types::Account, Billing::DeadUser)))
    end

    sig { returns(T::Boolean) }
    def show_actions_dropdown?
      payment.show_receipt_link? || payment.refundable? || payment.is_authorization?
    end

    sig { returns(T::Boolean) }
    def show_invoice_download_button?
      return false unless target
      !!current_user&.feature_enabled?(:billing_self_serve_invoice_download)
    end

    sig { params(transaction_id: Integer).returns(String) }
    def download_invoice_path(transaction_id:)
      required_target = T.must(target)
      if !required_target.is_a?(Billing::DeadUser) && required_target.business?
        self_serve_business_billing_download_invoices_path(required_target, transaction_id:)
      elsif required_target.organization?
        org_billing_download_invoices_path(required_target, transaction_id:)
      else
        user_billing_download_invoices_path(required_target, transaction_id:)
      end
    end

    sig { returns(T::Boolean) }
    private def render?
      show_actions_dropdown?
    end
  end
end
