# typed: strict
# frozen_string_literal: true

module Billing::Usage::Actions

  # Returns an account's Actions usage during the current billing cycle
  class FetchAccountUsage
    include ActionsHelper
    extend T::Sig

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
      response = Billing::Usage::FetchAccountUsage.new(account: account, products: ["actions"], starts_at: starts_at).call

      if response.success?
        usages = transform_actions_usages(response.content)

        Billing::Response.success(
          Billing::Usage::ActionsUsage.new(usages)
        )
      else
        Billing::Response.error(
          Billing::Usage::ActionsUsage.new(ZEROED_ACTIONS_USAGES)
        )
      end
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
    sig { params(account_usage: T::Array[Billing::Usage::AccountUsage]).returns(ActiveSupport::HashWithIndifferentAccess) }
    def transform_actions_usages(account_usage)
      product_usages = account_usage.flat_map(&:product_usages)
      transformed_actions_usages(usages: product_usages)
    end
  end
end
