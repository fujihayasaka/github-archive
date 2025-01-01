# typed: strict
# frozen_string_literal: true

module Billing::Usage::Actions

  # Returns Actions usage for a given account during the current billing cycle
  class FetchProductUsage
    include ActionsHelper

    sig { returns(Billing::Types::Account) }
    attr_reader :account

    sig { returns(Time) }
    attr_reader :starts_at

    sig do
      params(
        account:   T.any(User, Organization, Business),
        starts_at: T.nilable(Time)
      ).void
    end
    def initialize(account:, starts_at: nil)
      @account   = account
      @starts_at = T.let(starts_at || account.billable_owner.current_metered_billing_cycle_starts_at, Time)
    end

    sig { returns(Billing::Response) }
    def call
      response = Billing::Usage::FetchProductUsage.new(account: account, products: ["actions"], starts_at: starts_at).call

      if response.success?
        usages = transformed_actions_usages(usages: response.content)
        Billing::Response.success(
          T.unsafe(Billing::Usage::ActionsUsage.new(usages))
        )
      else
        Billing::Response.error(
          T.unsafe(Billing::Usage::ActionsUsage.new(ZEROED_ACTIONS_USAGES))
        )
      end
    end
  end
end
