# typed: true
# frozen_string_literal: true

module Billing
  module Platform
    module Api
      class DiscountLineItem
        def initialize(raw_discount_line_item)
          @raw_discount_line_item = raw_discount_line_item.with_indifferent_access
        end

        def to_json
          {
            sku: raw_discount_line_item[:sku],
            product: raw_discount_line_item[:product],
            quantity: raw_discount_line_item[:quantity],
            discountAmount: raw_discount_line_item[:discountAmount],
            usageAt: Time.at(0, raw_discount_line_item[:usageAt], :millisecond).utc,
            unitType: raw_discount_line_item[:unitType],
          }
        end

        private

        attr_reader :raw_discount_line_item
      end
    end
  end
end
