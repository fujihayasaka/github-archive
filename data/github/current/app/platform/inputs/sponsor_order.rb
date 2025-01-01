# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class SponsorOrder < Platform::Inputs::Base
      description "Ordering options for connections to get sponsor entities for GitHub Sponsors."
      visibility :public, environments: [:dotcom]
      visibility :internal, environments: [:enterprise]

      argument :field, Enums::SponsorOrderField, "The field to order sponsor entities by.", required: true
      argument :direction, Enums::OrderDirection, "The ordering direction.", required: true
    end
  end
end
