# typed: true
# frozen_string_literal: true

module Discussions
  class OverviewDiscussionComponent < ApplicationComponent
    include AvatarHelper

    attr_reader :discussion

    def initialize(discussion:)
      @discussion = discussion
    end

    private

    def discussion_participants
      discussion.participants_for(current_user)
    end

    def truncated_discussion_title
      helpers.truncate(discussion.title, length: 75)
    end

    def discussion_upvote_count
      helpers.discussion_social_count(discussion.total_upvotes)
    end

    def discussion_comment_count
      helpers.discussion_social_count(discussion.comment_count)
    end
  end
end
