# typed: strict
# frozen_string_literal: true

module Billing::Usage

  # Returns product usage for a given account during the current billing cycle
  class FetchProductUsage

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
      # list_product_usage has been removed as part of Meuse deprecation
      error = Billing::Api::ClientWrapper::BillingClientError.new("Meuse list_product_usage has been deprecated")
      Billing::Response.error(error)
    end

    private

    sig { returns(T.nilable(Billing::Types::Account)) }
    def owner
      account.billable_owner == account ? nil : account
    end
  end
end
