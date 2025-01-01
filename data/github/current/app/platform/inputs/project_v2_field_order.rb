# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class ProjectV2FieldOrder < Platform::Inputs::Base
      description "Ordering options for project v2 field connections"

      argument :field, Enums::ProjectV2FieldOrderField, "The field to order the project v2 fields by.", required: true
      argument :direction, Enums::OrderDirection, "The ordering direction.", required: true
    end
  end
end
