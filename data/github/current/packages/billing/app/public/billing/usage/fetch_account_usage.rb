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
      @starts_at = T.let(starts_at || account.billable_owner.current_metered_billing_cycle_starts_at, Time)
    end

    sig { returns(Billing::Response) }
    def call
      client_wrapper = Billing::Api::ClientWrapper.new(billable_owner: account.billable_owner, owner: owner)
      response = client_wrapper.list_account_usage(starts_at, product_names: products)

      return Billing::Response.error(response) if response.is_a?(Billing::Api::ClientWrapper::BillingClientError)

      Billing::Response.success(
        response[:account_usage].map { |usage| Billing::Usage::AccountUsage.new(usage) }
      )
    end

    private

    sig { returns(T.nilable(Billing::Types::Account)) }
    def owner
      account.billable_owner == account ? nil : account
    end
  end
end
