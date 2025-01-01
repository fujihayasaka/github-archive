# typed: true
# frozen_string_literal: true

module Billing
  module Settings
    module Codespaces
      class FooterComponent < ApplicationComponent
        attr_reader :spending_limit_path, :show_spending_limit, :show_projected_usage

        def initialize(
          account:,
          codespaces_usage:,
          spending_limit_path:,
          show_projected_usage: false
        )
          @account = account
          @budget = account.budget_for(group: :codespaces)
          @codespaces_usage = codespaces_usage
          @spending_limit_path = spending_limit_path
          @show_projected_usage = show_projected_usage
        end

        def show_billed_to_enterprise?
          return false unless @account&.feature_enabled?(:codespaces_billing_no_surprises)
          @account&.delegate_billing_to_business?
        end

        def enterprise_name
          @account&.billable_owner&.name || "enterprise"
        end

        def codespaces_total_monthly_cost
          return @codespaces_usage.total_paid_usage_cost unless @account&.feature_enabled?(:codespaces_billing_no_surprises)

          if @codespaces_usage.is_enterprise_org?
            @codespaces_usage.total_paid_usage_cost_for_enterprise_org_account
          else
            @codespaces_usage.total_paid_usage_cost
          end
        end

        def total_codespaces_cost
          ::Billing::Money.new(codespaces_total_monthly_cost).format(no_cents_if_whole: false)
        end

        def spending_limit_in_subunits
          @codespaces_usage.budget_limit
        end

        def unlimited_spending_limit?
          @codespaces_usage.has_unlimited_spending?
        end

        def border_classes
          classes = "Box rounded-top-0"
          classes += " rounded-bottom-0 border-top-0 border-bottom-0" if show_projected_usage
          classes
        end
      end
    end
  end
end
