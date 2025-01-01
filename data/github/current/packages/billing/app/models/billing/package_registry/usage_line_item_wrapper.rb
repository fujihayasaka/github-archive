# typed: true
# frozen_string_literal: true

module Billing
  module PackageRegistry
    class UsageLineItemWrapper < Billing::BaseUsageLineItemWrapper
      def downloaded_at
        usage_line_item.usage_at.to_time.utc
      end

      def sku_display_name
        "Data Transfer"
      end

      def registry_package_id
        usage_line_item.custom_fields["package.id"]&.to_i
      end

      def size_in_bytes
        usage_line_item.quantity
      end
    end
  end
end
