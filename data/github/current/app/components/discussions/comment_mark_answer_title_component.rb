# typed: true
# frozen_string_literal: true

module Discussions
  class CommentMarkAnswerTitleComponent < ApplicationComponent
    # comment - a DiscussionComment
    # timeline - a DiscussionTimeline
    def initialize(comment:, timeline:)
      @comment = comment
      @timeline = timeline
    end

    private

    attr_reader :comment, :timeline

    def render?
      comment && timeline&.show_discussion_mark_answer?(comment) && comment.answer?
    end

    memoize def user_who_marked_answer
      timeline.chosen_comment_selected_by_user
    end
  end
end
