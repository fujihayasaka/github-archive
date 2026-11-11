# typed: true
# frozen_string_literal: true

module Discussions
  class EditHistoryComponent < ApplicationComponent
    # discussion_or_comment - a Discussion or a DiscussionComment
    # timeline - a DiscussionTimeline
    def initialize(discussion_or_comment:, timeline:)
      @discussion_or_comment = discussion_or_comment
      @timeline = timeline
    end

    private

    attr_reader :discussion_or_comment, :timeline

    def render?
      discussion_or_comment && timeline && latest_edit
    end

    memoize def latest_edit
      timeline.latest_edit_for(discussion_or_comment)
    end

    memoize def latest_editor
      latest_edit.editor
    end

    # Returns the display name for the latest editor.
    # For AgenticApp bots, returns the display_name (e.g., "Claude").
    # For regular bots, returns the slug (without [bot] suffix).
    # For regular users, returns the display_login.
    def latest_editor_name
      editor = latest_editor
      return nil if editor.nil?

      if editor.is_a?(Bot)
        agentic_app = editor.async_agentic_app.sync
        agentic_app ? agentic_app.display_name : editor.slug
      else
        editor.display_login
      end
    end

    def editor_is_author?
      latest_edit.editor_id == discussion_or_comment.user_id
    end

    # Returns the full "edited by X" string for display.
    # For deleted editors, returns "edited by ghost".
    # For AgenticApp bots, returns "edited by <display_name>" (e.g., "edited by Claude").
    # For regular bots, returns "edited by <slug>".
    # For edits by the author, returns just "edited".
    # For other users, returns "edited by <display_login>".
    def edited_by
      editor = latest_editor
      if editor.nil?
        "edited by #{GitHub.ghost_user_login}"
      elsif editor_is_author?
        "edited"
      else
        "edited by #{latest_editor_name}"
      end
    end

    def history_log_path
      if discussion_or_comment.is_a?(Discussion)
        edits_log_discussion_path(timeline.repo_owner_login, timeline.repo_name, discussion_or_comment)
      else
        edits_log_discussion_comment_path(timeline.repo_owner_login, timeline.repo_name, timeline.discussion,
          discussion_or_comment)
      end
    end
  end
end
