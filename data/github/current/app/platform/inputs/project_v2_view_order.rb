# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class ProjectV2ViewOrder < Platform::Inputs::Base
      description "Ordering options for project v2 view connections"

      argument :field, Enums::ProjectV2ViewOrderField, "The field to order the project v2 views by.", required: true
      argument :direction, Enums::OrderDirection, "The ordering direction.", required: true
    end
  end
end
