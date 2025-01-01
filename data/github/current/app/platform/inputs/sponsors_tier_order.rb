# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class SponsorsTierOrder < Platform::Inputs::Base
      description "Ordering options for Sponsors tiers connections."
      visibility :public, environments: [:dotcom]
      visibility :internal, environments: [:enterprise]

      argument :field, Enums::SponsorsTierOrderField,
        "The field to order tiers by.", required: true
      argument :direction, Enums::OrderDirection, "The ordering direction.", required: true
    end
  end
end
