# typed: true
# frozen_string_literal: true

module Billing
  module Platform
    module Api
      class UsageLineItem
        def initialize(raw_usage_line_item)
          @raw_usage_line_item = raw_usage_line_item.with_indifferent_access
        end

        def to_json
          {
            billedAmount: raw_usage_line_item[:billedAmount],
            product: raw_usage_line_item[:product],
            quantity: raw_usage_line_item[:quantity],
            fullQuantity: raw_usage_line_item[:fullQuantity],
            appliedCostPerQuantity: raw_usage_line_item[:appliedCostPerQuantity],
            sku: raw_usage_line_item[:sku],
            friendlySkuName: raw_usage_line_item[:friendlySkuName],
            usageAt: Time.at(0, raw_usage_line_item[:usageAt], :millisecond).utc,
            unitType: raw_usage_line_item[:unitType],
          }
        end

        private

        attr_reader :raw_usage_line_item
      end
    end
  end
end
