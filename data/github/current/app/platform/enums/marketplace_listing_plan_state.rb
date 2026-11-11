# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class MarketplaceListingPlanState < Platform::Enums::Base
      description "The possible states of a Marketplace listing plan."
      visibility :internal

      value "DRAFT", "The owner is preparing the plan.", value: :draft
      value "PUBLISHED", "The owner has published the plan.", value: :published
      value "RETIRED", "The owner has retired the plan.", value: :retired
    end
  end
end
