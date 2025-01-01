# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class ProjectV2Order < Platform::Inputs::Base
      description "Ways in which lists of projects can be ordered upon return."

      argument :field, Enums::ProjectV2OrderField, "The field in which to order projects by.", required: true
      argument :direction, Enums::OrderDirection, "The direction in which to order projects by the specified field.", required: true
    end
  end
end
