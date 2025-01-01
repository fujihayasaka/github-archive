# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class ProjectV2WorkflowOrder < Platform::Inputs::Base
      description "Ordering options for project v2 workflows connections"

      argument :field, Platform::Enums::ProjectV2WorkflowsOrderField, "The field to order the project v2 workflows by.", required: true
      argument :direction, Enums::OrderDirection, "The ordering direction.", required: true
    end
  end
end
