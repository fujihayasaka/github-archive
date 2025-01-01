# typed: true
# frozen_string_literal: true

module Billing
  module Platform
    module Api
      class OtherUsageLineItem
        def initialize(raw_usage_line_item)
          @raw_usage_line_item = raw_usage_line_item.with_indifferent_access
        end

        def to_json
          {
            billedAmount: raw_usage_line_item[:billedAmount],
            usageAt: Time.at(0, raw_usage_line_item[:usageAt], :millisecond).utc,
          }
        end

        private

        attr_reader :raw_usage_line_item
      end
    end
  end
end
