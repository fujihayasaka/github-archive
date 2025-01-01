# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class DiscussionCommentOrder < Platform::Inputs::Base
      description "Ways in which lists of discussion comments can be ordered upon return."
      visibility :under_development

      argument :field, Enums::DiscussionCommentOrderField,
        "The field by which to order discussion comments.", required: true
      argument :direction, Enums::OrderDirection,
        "The direction in which to order discussion comments by the specified field.", required: true
    end
  end
end
