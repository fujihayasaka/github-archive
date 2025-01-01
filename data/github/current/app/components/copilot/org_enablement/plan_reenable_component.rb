# typed: strict
# frozen_string_literal: true

module Copilot
  module OrgEnablement
    class PlanReenableComponent < BaseActionDialog

      include GitHub::Memoizer

      sig { params(business: ::Business, organizations: T::Array[::Organization], copilot_plan: String).void }
      def initialize(business:, organizations:, copilot_plan:)
        super(business: business, organizations: organizations)
        @copilot_plan = copilot_plan
      end

      sig { returns(String) }
      memoize def title
        "Re-enable access to Copilot #{friendly_plan_name}"
      end

      sig { returns(String) }
      memoize def id
        "copilot-organization-reenable-dialog"
      end

      sig { returns(String) }
      memoize def confirmation_text
        "Confirm and restore seats"
      end

      sig { returns(String) }
      memoize def friendly_plan_name
        @copilot_plan.capitalize
      end

      sig { returns(Symbol) }
      def confirmation_scheme
        :primary
      end

      sig { returns(String) }
      def enablement
        @copilot_plan
      end

      sig { returns(Integer) }
      def plan_cost_per_seat
        @copilot_plan == "enterprise" ? Copilot::COPILOT_ENTERPRISE_MONTHLY_BASE_PRICE : Copilot::COPILOT_BUSINESS_MONTHLY_BASE_PRICE
      end
    end
  end
end
