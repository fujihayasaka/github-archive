# typed: true
# frozen_string_literal: true

module Platform
  module Connections
    class MarketplaceListing < Connections::Base
      description "Look up Marketplace Listings"

      total_count_field
    end
  end
end
