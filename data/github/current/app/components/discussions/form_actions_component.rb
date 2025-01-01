# typed: strict
# frozen_string_literal: true

module Discussions
  class FormActionsComponent < ApplicationComponent
    sig { params(timeline: DiscussionTimeline, is_inline_comment: T::Boolean).void }
    def initialize(timeline:, is_inline_comment:)
      @timeline = timeline
      @discussion = T.let(timeline.discussion, Discussion)
      @is_inline_comment = is_inline_comment
    end

    private

    sig { returns(DiscussionTimeline) }
    attr_reader :timeline

    sig { returns(Discussion) }
    attr_reader :discussion

    sig { returns(T::Boolean) }
    def inline_comment?
      @is_inline_comment
    end

    sig { returns(String) }
    def submit_button_text
      if inline_comment?
        "Reply"
      else
        "Comment"
      end
    end

    sig { returns(String) }
    def post_as_admin_action_text
      if inline_comment?
        "You're replying as "
      else
        "You're commenting as "
      end
    end

    sig { returns(T::Boolean) }
    memoize def show_close_button?
      return false if inline_comment?
      timeline.can_close_discussion?
    end

    sig { returns(T::Boolean) }
    memoize def show_reopen_button?
      return false if inline_comment?
      timeline.can_reopen_discussion?
    end
  end
end
