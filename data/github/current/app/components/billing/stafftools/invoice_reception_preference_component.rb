# typed: true
# frozen_string_literal: true

module Billing
  module Stafftools
    class InvoiceReceptionPreferenceComponent < ApplicationComponent

      sig { returns(T.any(User, Organization, Business)) }
      attr_reader :account

      sig { params(account: T.any(User, Organization, Business)).void }
      def initialize(account:)
        @account = account
      end

      sig { returns(String) }
      def form_path
        if account.organization?
          org_self_serve_invoicing_path(account)
        elsif account.business?
          business_self_serve_invoicing_path(account)
        else
          billing_self_serve_invoicing_path(account)
        end
      end

      sig { returns(T::Boolean) }
      def force_send_invoice_by_email?
        account.requires_invoice_by_email?
      end

      sig { returns(String) }
      def invoice_reception_status
        self_serve_invoice_enabled = account.self_serve_invoice_enabled? || force_send_invoice_by_email?
        self_serve_invoice_enabled ? "receiving" : "not receiving"
      end

      sig { returns(String) }
      def button_text
        return "Invoice preference change unavailable" if force_send_invoice_by_email?
        enable_or_disable = account_has_invoice_reception_enabled? ? "Disable" : "Enable"
        "#{enable_or_disable} Invoice Reception by Email"
      end

      sig { returns(T::Boolean) }
      def account_has_invoice_reception_enabled?
        account.self_serve_invoice_enabled?
      end
    end
  end
end
