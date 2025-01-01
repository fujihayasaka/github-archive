# typed: true
# frozen_string_literal: true

module Platform
  module Connections
    class MarketplaceListingPlan < Connections::Base
      description "A list of the payment plans for this Marketplace listing."
      visibility :internal

      total_count_field
    end
  end
end
