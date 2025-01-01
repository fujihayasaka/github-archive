# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class ProjectV2ItemOrder < Platform::Inputs::Base
      description "Ordering options for project v2 item connections"

      argument :field, Enums::ProjectV2ItemOrderField, "The field to order the project v2 items by.", required: true
      argument :direction, Enums::OrderDirection, "The ordering direction.", required: true
    end
  end
end
