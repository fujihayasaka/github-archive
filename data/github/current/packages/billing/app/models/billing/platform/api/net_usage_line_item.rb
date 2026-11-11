# typed: true
# frozen_string_literal: true

module Billing
  module Platform
    module Api
      class NetUsageLineItem
        def initialize(raw_net_usage_line_item)
          @raw_net_usage_line_item = raw_net_usage_line_item.with_indifferent_access
        end

        def to_json
          {
            entityId: raw_net_usage_line_item[:usageEntityId],
            grossAmount: raw_net_usage_line_item[:grossAmount],
            product: raw_net_usage_line_item[:product],
            quantity: raw_net_usage_line_item[:quantity],
            fullQuantity: raw_net_usage_line_item[:fullQuantity],
            discountAmount: raw_net_usage_line_item[:discountAmount],
            netAmount: raw_net_usage_line_item[:netAmount],
            appliedCostPerQuantity: raw_net_usage_line_item[:appliedCostPerQuantity],
            sku: raw_net_usage_line_item[:sku],
            friendlySkuName: raw_net_usage_line_item[:friendlySkuName],
            usageAt: Time.at(0, raw_net_usage_line_item[:usageAt], :millisecond).utc,
            unitType: raw_net_usage_line_item[:unitType],
            name: raw_net_usage_line_item[:name],
            dailyLicenseQuantity: raw_net_usage_line_item[:dailyLicenseQuantity],
            dailyLicenseCost: raw_net_usage_line_item[:dailyLicenseCost],
          }
        end

        private

        attr_reader :raw_net_usage_line_item
      end
    end
  end
end
