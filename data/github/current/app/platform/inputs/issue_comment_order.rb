# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class IssueCommentOrder < Platform::Inputs::Base
      description "Ways in which lists of issue comments can be ordered upon return."

      argument :field, Enums::IssueCommentOrderField, "The field in which to order issue comments by.", required: true
      argument :direction, Enums::OrderDirection, "The direction in which to order issue comments by the specified field.", required: true
    end
  end
end
