# typed: true
# frozen_string_literal: true

module Billing
  module MeteredUsage
    class BillableQuantityCalculatorResult
      # included_usage", "partial_overage", "overage", "over_budget"
      attr_reader :quantity, :reason

      def initialize(quantity:, reason:)
        @quantity = quantity
        @reason = reason
      end

      def to_attributes
        {
          billable_quantity: quantity,
          billable_quantity_reason: reason
        }
      end
    end
  end
end
