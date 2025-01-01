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

    def editor_is_author?
      latest_edit.editor_id == discussion_or_comment.user_id
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
