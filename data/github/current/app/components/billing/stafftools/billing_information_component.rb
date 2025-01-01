# typed: strict
# frozen_string_literal: true

module Billing
  module Stafftools
    class BillingInformationComponent < ApplicationComponent
      sig { returns(T.nilable(Billing::Types::Account)) }
      attr_reader :account

      sig { returns(T.nilable(Customer)) }
      attr_reader :customer

      sig { returns(T.nilable(Billing::Contact)) }
      attr_reader :billing_contact

      sig { returns(T.nilable(Billing::Contact)) }
      attr_reader :shipping_contact

      sig { params(account: T.nilable(Billing::Types::Account), enterprise_style: T::Boolean).void }
      def initialize(account:, enterprise_style: false)
        @account = account
        @customer = T.let(account&.customer, T.nilable(Customer))
        @billing_contact = T.let(customer&.billing_contact, T.nilable(Billing::Contact))
        @shipping_contact = T.let(customer&.shipping_contact&.persisted? ? customer&.shipping_contact : billing_contact, T.nilable(Billing::Contact))
        @enterprise_style = enterprise_style
      end


      sig { returns(T::Hash[String, Symbol]) }
      def styling
        if @enterprise_style
          {}
        else
          { font_size: :small, color: :muted }
        end
      end

      sig { returns(Symbol) }
      def font_weight_header
        if @enterprise_style
          :normal
        else
          :bold
        end
      end

      sig { returns(String) }
      def form_path
        required_account = T.must(account)
        if required_account.business?
          stafftools_enterprise_billing_sync_contact_information_path(required_account)
        else
          sync_contact_information_stafftools_user_path(required_account)
        end
      end

      private

      sig { returns(T::Boolean) }
      def render?
        return false if customer.nil?
        billing_contact&.persisted?
      end
    end
  end
end
