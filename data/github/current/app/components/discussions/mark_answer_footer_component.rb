# typed: true
# frozen_string_literal: true

module Discussions
  class MarkAnswerFooterComponent < ApplicationComponent
    delegate :author, to: :comment

    def initialize(comment:, timeline:, remote_form_id:)
      @comment = comment
      @timeline = timeline
      @remote_form_id = remote_form_id
    end

    private

    attr_reader :comment, :timeline, :remote_form_id

    def aria_label_mark_as_answer
      "Mark as answer: #{author}, #{timestamp}"
    end

    def aria_label_unmark_answer
      "Unmark as answer: #{author}, #{timestamp}"
    end

    def timestamp
      format = aria_label_date(comment.created_at)
      comment.created_at.to_formatted_s(format)
    end

    def show_discussion_comment_mark_answer_popover?
      return false unless logged_in?
      return false if current_user.dismissed_notice?(UserNotice::DISCUSSION_MARK_ANSWER_NOTICE)

      timeline.is_first_comment_markable_as_answer_on_the_page?(comment.id)
    end
  end
end
