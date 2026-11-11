# typed: true
# frozen_string_literal: true

module Billing
  module Settings
    class RemoveZeroDollarBudgetsBannerComponent < ApplicationComponent
      def initialize(entity: nil, current_user:, launched: false)
        @entity = entity
        @current_user = current_user
        @launched = launched
      end

      def render?
        customer = @entity&.customer
        customer.is_enterprise_or_org_with_budget_to_delete? && can_view_by_role?
      end

      def can_view_by_role?
        return false unless @current_user

        case @entity
        when Organization
          @entity.adminable_by?(@current_user)
        when Business
          @entity.owner?(@current_user)
        end
      end

      def copilot_policy_path
        case @entity
        when Business
          settings_copilot_enterprise_path(@entity, tab: "policies")
        when Organization
          settings_org_copilot_policies_path(@entity)
        else
          "https://docs.github.com/en/copilot"
        end
      end
    end
  end
end
