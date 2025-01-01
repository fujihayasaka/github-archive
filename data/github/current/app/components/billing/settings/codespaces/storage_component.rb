# typed: true
# frozen_string_literal: true

module Billing
  module Settings
    module Codespaces
      class StorageComponent < ApplicationComponent
        attr_reader :codespaces_usage, :show_spending, :account

        def initialize(
          account:,
          codespaces_usage: nil,
          show_spending: false
        )
          @account = account
          @codespaces_usage = codespaces_usage
          @show_spending = show_spending
        end

        def show_cost?
          return true if account.feature_enabled?(:codespaces_billing_no_surprises)

          !codespaces_usage.is_enterprise_org?
        end

        def included_usage?
          @codespaces_usage&.has_entitlements?
        end

        def storage_unrounded_usage
          @codespaces_usage&.storage_entitlement.consumed_quantity
        end

        def storage_usage_included
          @codespaces_usage&.storage_entitlement.allocated_quantity
        end

        # Raw quantity of entitlements displayed in the sku breakdown
        def storage_shared_sku_included
          storage_usage_skus.sum(0) { |sku| sku.entitlement_raw_quantity_consumed }
        end

        def codespaces_storage_total_monthly_cost
          return @codespaces_usage.total_storage_paid_usage_cost unless codespaces_usage.account&.feature_enabled?(:codespaces_billing_no_surprises)

          if @codespaces_usage.is_enterprise_org?
            @codespaces_usage.total_storage_paid_usage_cost_for_enterprise_org_account
          else
            @codespaces_usage.total_storage_paid_usage_cost
          end
        end

        # Paid quantity of usage displayed in the sku breakdown
        def storage_shared_sku_consumed
          if @codespaces_usage.is_enterprise_org?
            storage_usage_skus.sum(0) { |sku| sku.account_consumed_quantity }
          else
            storage_usage_skus.sum(0) { |sku| sku.overage_consumed_quantity }
          end
        end

        def storage_shared_sku_price
          return 0 unless storage_usage_skus.any?
          # storage price is the same
          storage_usage_skus.first.unit_price
        end

        def total_storage_cost
          ::Billing::Money.new(codespaces_storage_total_monthly_cost).format(no_cents_if_whole: false)
        end

        private

        def storage_usage_skus
          @codespaces_usage.storage_usages
        end
      end
    end
  end
end
