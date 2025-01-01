# typed: strict
# frozen_string_literal: true

module Billing::Usage

  # Returns a usage quote for an account's proposed usage during the current billing cycle
  class CalculateUsageQuotes
    extend T::Sig

    sig { returns(Billing::Types::Account) }
    attr_reader :account

    sig { returns(Billing::Types::ProposedUsage) }
    attr_reader :proposed_usage

    sig { returns(Time) }
    attr_reader :starts_at

    sig do
      params(
        account:        T.any(User, Organization, Business),
        proposed_usage: Billing::Types::ProposedUsage,
        starts_at:      T.nilable(Time)
      ).void
    end
    def initialize(account:, proposed_usage:, starts_at: nil)
      @account = account
      @proposed_usage = proposed_usage
      @starts_at = T.let(starts_at || account.billable_owner.current_metered_billing_cycle_starts_at, Time)
    end

    sig { returns(Billing::Response) }
    def call
      client_wrapper = Billing::Api::ClientWrapper.new(billable_owner: account.billable_owner, owner: owner)
      metered_cycle_starts_at = Google::Protobuf::Timestamp.new(seconds: starts_at.to_i)
      response = client_wrapper.calculate_usage_quotes(proposed_usage, metered_cycle_starts_at)

      return Billing::Response.error(response) if response.is_a?(Billing::Api::ClientWrapper::BillingClientError)

      Billing::Response.success(response[:usage_quotes])
    end

    private

    sig { returns(T.nilable(Billing::Types::Account)) }
    def owner
      account.billable_owner == account ? nil : account
    end
  end
end
