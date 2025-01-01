# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class CommitCommentOrder < Platform::Inputs::Base
      description "Ways in which lists of commit comments can be ordered upon return."

      argument :field, Enums::CommitCommentOrderField, "The field in which to order commit comments by.", required: true
      argument :direction, Enums::OrderDirection, "The direction in which to order commit comments by the specified field.", required: true
    end
  end
end
