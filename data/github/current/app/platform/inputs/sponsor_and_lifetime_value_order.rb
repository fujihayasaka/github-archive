# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class SponsorAndLifetimeValueOrder < Platform::Inputs::Base
      description "Ordering options for connections to get sponsor entities and associated USD amounts " \
        "for GitHub Sponsors."
      visibility :public, environments: [:dotcom]
      visibility :internal, environments: [:enterprise]

      argument :field, Enums::SponsorAndLifetimeValueOrderField, "The field to order results by.", required: true
      argument :direction, Enums::OrderDirection, "The ordering direction.", required: true
    end
  end
end
