# typed: true
# frozen_string_literal: true

module Billing
  class BaseUsageLineItemWrapper
    delegate_missing_to :@usage_line_item

    attr_reader :usage_line_item

    def initialize(usage_line_item)
      @usage_line_item = usage_line_item
    end

    def quantity
      usage_line_item.quantity
    end

    def usage_at
      usage_line_item.usage_at
    end

    def actor_id
      usage_line_item.actor_id
    end

    def owner_id
      usage_line_item.owner_id
    end

    def sku_name
      usage_line_item.product_sku.name
    end

    def repository_id
      usage_line_item.repository_id.positive? ? usage_line_item.repository_id : nil
    end

    def multiplier
      usage_line_item.product_sku.product_rate_plans[0].multiplier
    end

    def rate_plan_unit_price
      usage_line_item.rate_plan_unit_price
    end

    def to_hash
      {
        usage_line_item: @usage_line_item.to_h
      }
    end
  end
end
