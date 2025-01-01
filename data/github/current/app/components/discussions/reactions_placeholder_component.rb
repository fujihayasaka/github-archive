# typed: true
# frozen_string_literal: true

module Discussions
  class ReactionsPlaceholderComponent < ApplicationComponent
    # target - a Discussion or DiscussionComment
    # timeline_or_feed - a DiscussionTimeline or DiscussionIndexFeed
    def initialize(target:, timeline_or_feed:)
      @target = target
      @timeline_or_feed = timeline_or_feed
    end

    private

    attr_reader :target, :timeline_or_feed

    delegate :user_feature_enabled?, to: :helpers

    def deferred_content_path
      helpers.cached_path(:reactions_discussion_path,
        user_id: timeline_or_feed.repo_owner_login,
        repository: timeline_or_feed.repo_name,
        number: discussion_number)
    end

    def deferred_content_inputs
      if target.is_a?(Discussion)
        { discussion_id: target.id }
      else
        { comment_id: target.id }
      end
    end

    memoize def comment_is_nested?
      target.is_a?(DiscussionComment) && target.nested?
    end

    def discussion_number
      if timeline_or_feed.is_a?(DiscussionTimeline)
        timeline_or_feed.discussion_number
      else
        target.number
      end
    end

    def viewer_can_react
      logged_in?
    end

    def show_reaction_button
      !comment_is_nested?
    end

    def reaction_count(emotion)
      timeline_or_feed.fast_reactions_for(target)[emotion.content]
    end
  end
end
