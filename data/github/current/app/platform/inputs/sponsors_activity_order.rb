# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class SponsorsActivityOrder < Platform::Inputs::Base
      description "Ordering options for GitHub Sponsors activity connections."
      visibility :public, environments: [:dotcom]
      visibility :internal, environments: [:enterprise]

      argument :field, Enums::SponsorsActivityOrderField,
        "The field to order activity by.", required: true
      argument :direction, Enums::OrderDirection, "The ordering direction.", required: true
    end
  end
end
