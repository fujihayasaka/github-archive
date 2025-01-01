# typed: strict
# frozen_string_literal: true

module Platform
  module Inputs
    class GistCommentOrder < Platform::Inputs::Base
      description "Ways in which lists of gist comments can be ordered upon return."

      argument :field, Enums::GistCommentOrderField,
        "The field by which to order gist comments.", required: true
      argument :direction, Enums::OrderDirection,
        "The direction in which to order gist comments by the specified field.", required: true
    end
  end
end
