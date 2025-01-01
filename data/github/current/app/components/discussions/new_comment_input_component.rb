# typed: true
# frozen_string_literal: true

module Discussions
  class NewCommentInputComponent < ApplicationComponent
    # timeline - a DiscussionTimeline
    def initialize(timeline:)
      @timeline = timeline
    end

    private

    attr_reader :timeline

    def render?
      timeline && repository && logged_in? && !timeline.locked_on_migration_repo?
    end

    delegate :repository, :locked_discussion?, to: :timeline

    memoize def emu_contribution_blocked?
      helpers.emu_contribution_blocked?(repository)
    end

    memoize def viewer_must_verify_email?
      current_user.should_verify_email?
    end

    def heading
      supports_mark_as_answer? ? "Suggest an answer" : "Add a comment"
    end

    def placeholder
      supports_mark_as_answer? ? "Add your answer here..." : "Add your comment here..."
    end

    memoize def supports_mark_as_answer?
      timeline.supports_mark_as_answer?
    end

    def comment_form_shown?
      timeline.can_interact_with_repo? && !emu_contribution_blocked? && !viewer_must_verify_email? &&
        !timeline.archived_repo? && !locked_discussion? && !timeline.blocked_from_commenting?
    end

    def slash_commands_enabled?
      current_user.slash_commands_enabled? || repository.slash_commands_enabled?
    end

    # Private: Get HTML-safe Hydro `data` attributes for clicking something on an individual
    # discussion page.
    #
    # discussion_or_comment - a Discussion or DiscussionComment
    # target - a Symbol from the `DISCUSSION_CLICK_EVENT_TARGETS` list representing
    #          what was clicked
    #
    # Returns a String.
    def safe_discussion_view_click_attrs(discussion_or_comment, target:)
      safe_data_attributes(helpers.discussion_view_click_attrs(discussion_or_comment, target: target))
    end
  end
end
