# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class TeamDiscussionCommentOrder < Platform::Inputs::Base
      description "Ways in which team discussion comment connections can be ordered."

      argument :field, Enums::TeamDiscussionCommentOrderField, "The field by which to order nodes.", required: true
      argument :direction, Enums::OrderDirection, "The direction in which to order nodes.", required: true
    end
  end
end
