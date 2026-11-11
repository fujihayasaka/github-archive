# typed: true
# frozen_string_literal: true

module Discussions
  class DeferredActionsMenuComponent < ApplicationComponent
    include KeyboardShortcutsHelper

    # discussion_or_comment - a Discussion or a DiscussionComment
    # timeline - a DiscussionTimeline
    def initialize(discussion_or_comment:, timeline:)
      @discussion_or_comment = discussion_or_comment
      @timeline = timeline
    end

    private

    attr_reader :discussion_or_comment, :timeline

    delegate :repo_owner_login, :repo_name, :discussion_number, to: :timeline

    def render?
      discussion_or_comment && timeline
    end

    def form_path
      if discussion_or_comment.is_a?(DiscussionComment)
        discussion_comment_path(repo_owner_login, repo_name, discussion_number, discussion_or_comment)
      else
        discussion_path(discussion_number, timeline.repository)
      end
    end

    def comment_actions_url
      if discussion_or_comment.is_a?(DiscussionComment)
        discussion_comment_actions_menu_path(repo_owner_login, repo_name, discussion_number, discussion_or_comment,
          form_path: form_path)
      else
        discussion_actions_menu_path(repo_owner_login, repo_name, discussion_number,
          form_path: form_path)
      end
    end

    def target_class
      discussion_or_comment.is_a?(Discussion) ? "Discussion" : "Comment"
    end
  end
end
