# typed: true
# frozen_string_literal: true

module Discussions
  class SpammyBadgeComponent < ApplicationComponent
    # discussion_or_comment - a Discussion or DiscussionComment
    def initialize(discussion_or_comment:)
      @discussion_or_comment = discussion_or_comment
    end

    private

    attr_reader :discussion_or_comment

    def render?
      logged_in? && discussion_or_comment.spammy? && current_user.site_admin?
    end
  end
end
