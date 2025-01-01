# typed: true
# frozen_string_literal: true

module PullRequests
  class LegacyReviewThreadComponent < ApplicationComponent
    include AvatarHelper

    attr_reader :pull_request, :pull_request_review_thread, :first_comment

    def initialize(review_thread:)
      @pull_request_review_thread = review_thread
      @pull_request = review_thread.pull_request
      @first_comment = review_thread.async_first_comment.sync
    end

    memoize def author
      first_comment.user || User.ghost
    end

    def anchor
      "diff-for-comment-#{first_comment.id}"
    end

    def discussion_anchor
      "discussion-diff-#{first_comment.id}"
    end

    def diff_path
      pull_request_review_thread.async_original_diff_file_path_uri.sync || # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        pull_request_review_thread.async_current_diff_file_path_uri.sync
    end
  end
end
