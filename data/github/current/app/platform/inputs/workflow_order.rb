# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class WorkflowOrder < Platform::Inputs::Base
      description "Ways in which lists of workflows can be ordered upon return."

      argument :field, Enums::WorkflowOrderField, "The field by which to order workflows.",
        required: true
      argument :direction, Enums::OrderDirection,
        "The direction in which to order workflows by the specified field.", required: true
    end
  end
end
