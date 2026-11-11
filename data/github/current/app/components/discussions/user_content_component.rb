# typed: true
# frozen_string_literal: true

module Discussions
  # Renders the necessary scaffolding for machine-translating the body of a discussion or comment
  # and a BodyAndPollComponent for the actual body and poll content of the item.
  class UserContentComponent < ApplicationComponent
    # discussion_or_comment - a Discussion or DiscussionComment
    # timeline - a DiscussionTimeline
    def initialize(discussion_or_comment:, timeline:)
      @discussion_or_comment = discussion_or_comment
      @timeline = timeline
    end

    private

    attr_reader :discussion_or_comment, :timeline

    def render?
      discussion_or_comment.present? && timeline.present?
    end

    memoize def body_html
      timeline.body_html_for(discussion_or_comment)
    end

    memoize def translation_type
      discussion_or_comment.is_a?(DiscussionComment) ? "comment" : "discussion"
    end

    memoize def localization_config
      helpers.localization_config
    end

    def discussion_or_comment_detect_language_path
      if discussion_or_comment.is_a?(Discussion)
        discussion_language_detections_path(discussion_or_comment.repository_owner_login,
          discussion_or_comment.repository, discussion_or_comment)
      else
        discussion_comment_language_detections_path(discussion_or_comment.repository_owner_login,
          discussion_or_comment.repository, discussion_or_comment.discussion, discussion_or_comment)
      end
    end
  end
end
