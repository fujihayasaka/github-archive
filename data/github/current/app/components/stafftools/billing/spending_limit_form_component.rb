# typed: true
# frozen_string_literal: true

module Stafftools
  module Billing
    class SpendingLimitFormComponent < ApplicationComponent
      attr_reader :budget_group, :enforce_spending_limit, :product_name, :form_action

      def initialize(
        budget_group:,
        product_name:,
        form_action:,
        spending_limit_in_subunits: 0,
        enforce_spending_limit: true,
        disabled: false
      )
        @budget_group = budget_group
        @product_name = product_name
        @form_action = form_action
        @enforce_spending_limit = enforce_spending_limit
        @spending_limit_in_subunits = spending_limit_in_subunits
        @disabled = disabled
      end

      def disabled?
        @disabled
      end

      # Set form elements (input, button, etc.) as disabled only if disabled? is true
      def disabled_attribute
        disabled? ? "disabled" : ""
      end

      def spending_limit_value
        number_with_precision(@spending_limit_in_subunits / 100.0, precision: 2)
      end
    end
  end
end
