# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class MarketplaceListingOrder < Platform::Inputs::Base
      description "Ordering options for Marketplace listings."
      visibility :internal

      argument :field, Enums::MarketplaceListingOrderField, "The field to order listings by.", required: true
      argument :direction, Enums::OrderDirection, "The ordering direction.", required: true
    end
  end
end
