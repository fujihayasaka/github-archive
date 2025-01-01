# typed: true
# frozen_string_literal: true

module Pricing
  class AnnualDiscountNoticeComponent < PriceTagComponent
    def render?
      !GitHub.enterprise?
    end
  end
end
