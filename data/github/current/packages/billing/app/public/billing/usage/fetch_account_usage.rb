# typed: strict
# frozen_string_literal: true

module Billing::Usage

  # Returns an account's usage of the given products during the current billing cycle
  class FetchAccountUsage

    sig { returns(Billing::Types::Account) }
    attr_reader :account

    sig { returns(T::Array[T.any(String, Symbol)]) }
    attr_reader :products

    sig { returns(Time) }
    attr_reader :starts_at

    sig do
      params(
        account:   Billing::Types::Account,
        products:  T::Array[T.any(String, Symbol)],
        starts_at: T.nilable(Time)
      ).void
    end
    def initialize(account:, products:, starts_at: nil)
      @account   = account
      @products  = products
      @starts_at = T.let(starts_at || account.billable_owner.current_metered_billing_cycle_starts_at.to_time, Time)
    end

    sig { returns(Billing::Response) }
    def call
      # list_account_usage has been removed as part of Meuse deprecation
      # Return error to match existing behavior
      error = Billing::Api::ClientWrapper::BillingClientError.new("Meuse list_account_usage has been deprecated and is no longer available")
      Billing::Response.error(error)
    end

    private

    sig { returns(T.nilable(Billing::Types::Account)) }
    def owner
      account.billable_owner == account ? nil : account
    end
  end
end
