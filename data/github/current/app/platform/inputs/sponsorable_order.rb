# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class SponsorableOrder < Platform::Inputs::Base
      docs_category :sponsors
      description "Ordering options for connections to get sponsorable entities for GitHub Sponsors."
      visibility :public, environments: [:dotcom]
      visibility :internal, environments: [:enterprise]

      argument :field, Enums::SponsorableOrderField,
        "The field to order sponsorable entities by.", required: true
      argument :direction, Enums::OrderDirection, "The ordering direction.", required: true
    end
  end
end
