# typed: strict
# frozen_string_literal: true

module Stafftools
  module Billing
    class RemovePaymentMethodComponent < ApplicationComponent

      sig do
        params(account: ::Billing::Types::Account, scheme: T.nilable(Symbol), action_text: String)
          .void
      end
      def initialize(account:, scheme: nil, action_text: "Remove")
        @account = account
        @scheme = scheme
        @action_text = action_text
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def show_button_attributes
        attrs = { color: :danger, test_selector: "remove-payment-method-link" }
        if scheme
          attrs[:sceheme] = scheme
        end

        attrs
      end

      private

      sig { returns(::Billing::Types::Account) }
      attr_reader :account

      sig { returns(T.nilable(Symbol)) }
      attr_reader :scheme

      sig { returns(String) }
      attr_reader :action_text

      sig { returns(T::Boolean) }
      def render?
        account.has_valid_payment_method?(feature_type: :noncommercial)
      end
    end
  end
end
