# typed: true
# frozen_string_literal: true

module Discussions
  class AuthorBadgesComponent < ApplicationComponent
    # discussion_or_comment - a Discussion or DiscussionComment
    # timeline - a DiscussionTimeline
    def initialize(discussion_or_comment:, timeline:)
      @discussion_or_comment = discussion_or_comment
      @timeline = timeline
    end

    private

    attr_reader :discussion_or_comment, :timeline

    def render?
      discussion_or_comment && timeline
    end

    memoize def author
      discussion_or_comment.author
    end
  end
end
