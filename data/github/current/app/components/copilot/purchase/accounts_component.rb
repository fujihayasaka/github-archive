# typed: strict
# frozen_string_literal: true

module Copilot
  module Purchase
    class AccountsComponent < ApplicationComponent
      sig { returns(T.any(::Organization, ::Business)) }
      attr_reader :account

      sig do
        params(
          selected_account: T.any(::Organization, ::Business),
          eligibility: Copilot::Purchase::Eligibility::EligibilityReason
        ).void
      end
      def initialize(selected_account:, eligibility:)
        @account = selected_account
        @eligibility = eligibility
      end

      sig { returns(Copilot::Purchase::Eligibility::EligibilityReason) }
      def account_eligibility
        @eligibility
      end
    end
  end
end
