# typed: true
# frozen_string_literal: true

module Discussions
  class BadgesPlaceholderComponent < ApplicationComponent
    # target - a Discussion or DiscussionComment
    # timeline - a DiscussionTimeline
    def initialize(target:, timeline:)
      @target = target
      @timeline = timeline
    end

    private

    attr_reader :timeline, :target

    def render?
      logged_in?
    end

    def deferred_content_path
      helpers.cached_path(:discussions_badges_path,
        user_id: timeline.repo_owner_login,
        repository: timeline.repo_name)
    end

    def deferred_content_inputs
      if target.is_a?(Discussion)
        { discussion_id: target.id }
      else
        { comment_id: target.id }
      end
    end
  end
end
