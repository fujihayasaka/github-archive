# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class TeamMemberOrder < Platform::Inputs::Base
      description "Ordering options for team member connections"

      argument :field, Enums::TeamMemberOrderField, "The field to order team members by.", required: true
      argument :direction, Enums::OrderDirection, "The ordering direction.", required: true
    end
  end
end
