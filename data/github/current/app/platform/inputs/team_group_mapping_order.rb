# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class TeamGroupMappingOrder < Platform::Inputs::Base
      visibility :under_development
      description "Ordering options for team group mapping connections"

      argument :field, Enums::TeamGroupMappingOrderField, "The field to order team group mappings by.", required: true
      argument :direction, Enums::OrderDirection, "The ordering direction.", required: true
    end
  end
end
