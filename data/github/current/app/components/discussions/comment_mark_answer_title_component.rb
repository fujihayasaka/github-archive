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
      return timeline.chosen_comment_selected_by_user unless helpers.posted_as_admin?(comment)

      safe_join(["Admin", helpers.discussion_dot_divider, timeline.chosen_comment_selected_by_user])
    end

    def verified_answer?
      timeline.show_as_verified_answer?(comment)
    end

    def answer_label
      if user_who_marked_answer
        verified_answer? ? "Answer verified by" : "Answer selected by"
      else
        verified_answer? ? "Answer verified" : "Answer selected"
      end
    end

    def profile_link_user
      verified_answer? ? helpers.user_who_verified_answer(timeline) : user_who_marked_answer
    end

    def should_show_timestamp?
      verified_answer? && user_who_marked_answer
    end

    def should_show_profile_link?
      user_who_marked_answer
    end
  end
end
