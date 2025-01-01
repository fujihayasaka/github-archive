# typed: strict
# frozen_string_literal: true

module Copilot
  module Purchase
    class AccountComponent < ApplicationComponent

      include Copilot::Purchase::Helpers

      sig { returns(T.any(::Organization, ::Business)) }
      attr_reader :account

      sig { returns(T::Array[(T::Hash[Symbol, String])]) }
      attr_reader :accounts

      sig do
        params(
          accounts: T::Array[(T::Hash[Symbol, String])],
          selected_account: T.any(::Organization, ::Business),
          eligibility: Copilot::Purchase::Eligibility::EligibilityReason
        ).void
      end
      def initialize(accounts:, selected_account:, eligibility:)
        @accounts = accounts
        @account = selected_account
        @eligibility = eligibility
      end

      sig { returns(Copilot::Purchase::Eligibility::EligibilityReason) }
      def account_eligibility
        @eligibility
      end

      sig { params(other_account: T::Hash[Symbol, String]).returns(T::Boolean) }
      def account_is_selected?(other_account)
        account_name(@account) == other_account[:slug] && account_type(@account) == other_account[:type]
      end
    end
  end
end
