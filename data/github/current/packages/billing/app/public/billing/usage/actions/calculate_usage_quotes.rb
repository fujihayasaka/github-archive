# typed: strict
# frozen_string_literal: true

module Billing::Usage::Actions

  # Returns a usage quote for an account's proposed Actions usage during the current billing cycle
  class CalculateUsageQuotes
    include ActionsHelper

    sig { returns(Billing::Types::Account) }
    attr_reader :account

    sig { returns(Billing::Types::ProposedUsage) }
    attr_reader :proposed_usage

    sig { returns(Time) }
    attr_reader :starts_at

    sig do
      params(
        account: Billing::Types::Account,
        proposed_usage: T::Array[{
          proposed_quantity:    Billing::Types::Numeric,
          entitlement_quantity: Billing::Types::Numeric,
          product_sku_name:     T.any(String, Symbol)
        }],
        starts_at: T.nilable(Time)
      ).void
    end
    def initialize(account:, proposed_usage:, starts_at: nil)
      @account = account
      @proposed_usage = T.let(
        proposed_usage.map { |usage| { **usage, product_name: "actions" } },
        Billing::Types::ProposedUsage
      )
      @starts_at = T.let(starts_at || account.billable_owner.current_metered_billing_cycle_starts_at, Time)
    end

    sig { returns(Billing::Response) }
    def call
      response = Billing::Usage::CalculateUsageQuotes.new(account: account, proposed_usage: proposed_usage, starts_at: starts_at).call

      # The current behavior is to return nothing if there's an error
      return response if response.error?

      Billing::Response.success(
        Billing::Usage::ActionsUsage.new(transform_actions_usages(response.content))
      )
    end

    private

    # Transforms the usages into our formatted product_skus and effective quantities
    # {
    #   "UBUNTU" => linux_effective_quantity,
    #   "MACOS" => macos_effective_quantity,
    #   "WINDOWS" => windows_effective_quantity,
    #   "ubuntu_4_core" => linux_4_core_effective_quantity,
    #   "ubuntu_8_core" => linux_8_core_effective_quantity,
    #   "ubuntu_16_core" => linux_16_core_effective_quantity,
    #   "ubuntu_32_core" => linux_32_core_effective_quantity,
    #   "ubuntu_64_core" => linux_64_core_effective_quantity,
    #   "windows_4_core" => windows_4_core_effective_quantity,
    #   "windows_8_core" => windows_8_core_effective_quantity,
    #   "windows_16_core" => windows_16_core_effective_quantity,
    #   "windows_32_core" => windows_32_core_effective_quantity,
    #   "windows_64_core" => windows_64_core_effective_quantity,
    #   "total" => total_with_entitlements + total_without_entitlements
    # }
    sig do
      params(
        usage_quotes: T::Array[Billing::Usage::UsageQuote],
        method:       Symbol,
      ).returns(ActiveSupport::HashWithIndifferentAccess)
    end
    def transform_actions_usages(usage_quotes, method: :effective_quantity)
      sku_quantities = Billing::Actions::MEUSE_RUNNERS.map do |sku_name|
        quantity = usage_quotes.detect { |usage| usage.product_sku_name == sku_name }&.proposed_effective_quantity || 0
        [serialize_product_sku_name(sku_name), quantity]
      end.to_h.with_indifferent_access.merge(total: usage_quotes.sum(&:proposed_effective_quantity))
    end
  end
end
