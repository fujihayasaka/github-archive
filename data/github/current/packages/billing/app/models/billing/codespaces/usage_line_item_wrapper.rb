# typed: true
# frozen_string_literal: true

module Billing::Codespaces
  class UsageLineItemWrapper < Billing::BaseUsageLineItemWrapper

    STORAGE = "storage"
    PREBUILD_STORAGE = "prebuild_storage"

    def end_time
      usage_line_item.usage_at.to_time.utc
    end

    def usage
      usage_line_item.quantity
    end

    def unit_type
      if [STORAGE, PREBUILD_STORAGE].include?(usage_line_item.product_sku.name)
        "gb-month"
      else
        "hour"
      end
    end

    def sku_display_name
      name = usage_line_item.product_sku.name
      if name.starts_with? "compute_d"
        return name.gsub("compute_d", "Compute - ").concat " core"
      end
      if name == PREBUILD_STORAGE
        return "Prebuild storage"
      end

      name.capitalize
    end

    def action_workflow_name
      name = usage_line_item.product_sku.name
      if name == PREBUILD_STORAGE
        Codespaces::Prebuilds::WORKFLOW_SLUG.titleize
      end
    end
  end
end
