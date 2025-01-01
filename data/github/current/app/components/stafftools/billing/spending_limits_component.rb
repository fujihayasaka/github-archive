# typed: true
# frozen_string_literal: true

module Stafftools
  module Billing
    class SpendingLimitsComponent < ApplicationComponent
      def initialize(user:)
        @user = user
      end

      memoize def codespaces_budget
        @user.budget_for(group: :codespaces)
      end

      memoize def actions_and_packages_budget
        @user.budget_for(group: :shared)
      end

      def disabled?
        !@user.has_valid_payment_method? || @user.is_organization_billed_through_business?
      end
    end
  end
end
