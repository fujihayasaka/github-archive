# typed: true
# frozen_string_literal: true

module Stafftools
  module Businesses
    module Marketplace
      class UsageComponent < ApplicationComponent
        include GitHub::Memoizer

        attr_reader :business, :marketplace_items

        def initialize(business:, marketplace_items:)
          @business = business
          @marketplace_items = marketplace_items
        end
      end
    end
  end
end
