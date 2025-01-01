# typed: true
# frozen_string_literal: true

module Billing
  module Settings
    module Codespaces
      class ComputeComponent < ApplicationComponent
        attr_reader :account, :codespaces_usage, :show_spending

        def initialize(
          account:,
          codespaces_usage: nil,
          show_spending: false
        )
          @account = account
          @codespaces_usage = codespaces_usage
          @show_spending = show_spending
        end

        def show_totals?
          return true if account&.feature_flag_enabled_or_raise?(:codespaces_billing_no_surprises) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage

          !codespaces_usage.is_enterprise_org?
        end

        def included_usage?
          @codespaces_usage&.has_entitlements?
        end

        def compute_unrounded_usage
          @codespaces_usage&.compute_entitlement.consumed_quantity
        end

        def compute_usage_included
          @codespaces_usage&.compute_entitlement.allocated_quantity
        end

        def compute_usage_skus
          @codespaces_usage.compute_usages
        end

        def codespaces_compute_total_monthly_cost
          return @codespaces_usage.total_compute_paid_usage_cost unless account&.feature_flag_enabled_or_raise?(:codespaces_billing_no_surprises) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage

          if @codespaces_usage.is_enterprise_org?
            @codespaces_usage.total_compute_paid_usage_cost_for_enterprise_org_account
          else
            @codespaces_usage.total_compute_paid_usage_cost
          end
        end

        def total_compute_cost
          ::Billing::Money.new(codespaces_compute_total_monthly_cost).format(no_cents_if_whole: false)
        end
      end
    end
  end
end
