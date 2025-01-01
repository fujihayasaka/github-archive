# typed: true
# frozen_string_literal: true

module Billing
  module Platform
    module Api
      class NetUsageLineItem
        def initialize(raw_net_usage_line_item, org_or_repo_request: false)
          @raw_net_usage_line_item = raw_net_usage_line_item.with_indifferent_access
          @org_or_repo_request = org_or_repo_request
        end

        def to_json
          {
            entityId: raw_net_usage_line_item[:usageEntityId],
            grossAmount: raw_net_usage_line_item[:grossAmount],
            product: raw_net_usage_line_item[:product],
            quantity: raw_net_usage_line_item[:quantity],
            fullQuantity: raw_net_usage_line_item[:fullQuantity],
            discountAmount: discount_amount,
            netAmount: net_amount,
            appliedCostPerQuantity: raw_net_usage_line_item[:appliedCostPerQuantity],
            sku: raw_net_usage_line_item[:sku],
            friendlySkuName: raw_net_usage_line_item[:friendlySkuName],
            usageAt: Time.at(0, raw_net_usage_line_item[:usageAt], :millisecond).utc,
            unitType: raw_net_usage_line_item[:unitType],
            name: raw_net_usage_line_item[:name],
          }
        end

        private

        attr_reader :raw_net_usage_line_item, :org_or_repo_request

        def net_amount
          # since we don't have discount items at the org and repo level, we don't want to show the net amount
          org_or_repo_request ? nil : raw_net_usage_line_item[:netAmount]
        end

        def discount_amount
          # since we don't have discount items at the org and repo level, we don't want to show them
          org_or_repo_request ? nil : raw_net_usage_line_item[:discountAmount]
        end
      end
    end
  end
end
