# typed: strict
# frozen_string_literal: true

module Billing
  module Settings
    class SponsorsOverview::FooterComponent < ApplicationComponent
      include SponsorsButtonsHelper

      sig { params(account: User, amount: Billing::Money).void }
      def initialize(account:, amount:)
        @account = account
        @amount  = amount
      end

      private

      sig { returns(User) }
      attr_reader :account

      sig { returns(Billing::Money) }
      attr_reader :amount

      sig { returns(T::Boolean) }
      def show_switch_to_invoiced_billing_link?
        account.can_switch_to_sponsors_invoicing?
      end

      sig { returns(String) }
      def switch_to_invoiced_billing_link
        org_sponsoring_billing_options_path(account)
      end

      sig { returns(T::Boolean) }
      def show_create_invoice_link?
        account.sponsors_invoiced?
      end
    end
  end
end
