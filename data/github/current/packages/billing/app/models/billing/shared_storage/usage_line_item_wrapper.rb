# typed: true
# frozen_string_literal: true

module Billing::SharedStorage
  class UsageLineItemWrapper < Billing::BaseUsageLineItemWrapper
    def aggregate_effective_at
      usage_line_item.usage_at.to_time.utc
    end

    def sku_display_name
      "Shared Storage"
    end

    def size_in_bytes
      usage_line_item.quantity
    end
  end
end
