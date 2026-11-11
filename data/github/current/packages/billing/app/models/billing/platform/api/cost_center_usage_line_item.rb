# typed: true
# frozen_string_literal: true

module Billing
  module Platform
    module Api
      class CostCenterUsageLineItem
        def initialize(raw_usage_line_item, customer_id)
          @raw_usage_line_item = raw_usage_line_item.with_indifferent_access
          @customer_id = customer_id
        end

        # Transform cost center API response to format expected by the React UsageTable component
        def to_json
          {
            entityId: raw_usage_line_item[:costCenterId],
            costCenterId: raw_usage_line_item[:costCenterId],
            costCenterName: raw_usage_line_item[:costCenterName],
            customerId: customer_id,
            name: raw_usage_line_item[:costCenterName],
            billedAmount: raw_usage_line_item[:billedAmount],
            totalAmount: raw_usage_line_item[:netAmount],
            discountAmount: raw_usage_line_item[:discountAmount],
            usageAt: parse_usage_at(raw_usage_line_item[:usageAt]),
            # Set default values for other fields expected by the React component
            appliedCostPerQuantity: 0,
            quantity: 0,
            fullQuantity: 0,
            usageType: "topcostcenter"
            # Note: intentionally NOT including sku, product, org fields so React can identify this
            # as a CostCenterUsageLineItem (distinct from ProductUsageLineItem which has sku)
          }
        end

        private

        attr_reader :raw_usage_line_item, :customer_id

        def parse_usage_at(value)
          return nil if value.nil?

          Time.at(0, value, :millisecond).utc
        end
      end
    end
  end
end
