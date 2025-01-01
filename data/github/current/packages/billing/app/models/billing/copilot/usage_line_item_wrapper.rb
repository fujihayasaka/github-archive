# typed: true
# frozen_string_literal: true

module Billing::Copilot
  class UsageLineItemWrapper < Billing::BaseUsageLineItemWrapper
    def end_time
      usage_line_item.usage_at.to_time.utc
    end

    def usage
      usage_line_item.quantity
    end

    def sku_display_name
      case usage_line_item.product_sku.name
      when "copilot_enterprise"
        "Copilot Enterprise"
      when "copilot_standalone", "copilot_for_business" # Copilot Standalone and Copilot Business are different skus, but will be identified the same way for the customer
        "Copilot Business"
      else
        "Copilot"
      end
    end
  end
end
