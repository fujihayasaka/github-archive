# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class WorkflowRunOrder < Platform::Inputs::Base
      description "Ways in which lists of workflow runs can be ordered upon return."

      argument :field, Enums::WorkflowRunOrderField, "The field by which to order workflows.",
        required: true
      argument :direction, Enums::OrderDirection,
        "The direction in which to order workflow runs by the specified field.", required: true
    end
  end
end
