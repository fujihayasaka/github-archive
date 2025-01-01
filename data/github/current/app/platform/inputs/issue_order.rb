# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class IssueOrder < Platform::Inputs::Base
      description "Ways in which lists of issues can be ordered upon return."

      argument :field, Enums::IssueOrderField, "The field in which to order issues by.", required: true
      argument :direction, Enums::OrderDirection, "The direction in which to order issues by the specified field.", required: true
    end
  end
end
