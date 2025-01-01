# typed: true
# frozen_string_literal: true

module PullRequests
  class ReviewPagedThreadsComponent < ApplicationComponent
    attr_reader :pull_request, :pull_request_review, :page_info

    def initialize(pull_request_review:, pull_request:, page_info:)
      @pull_request = pull_request
      @pull_request_review = pull_request_review
      @page_info = page_info
    end

    memoize def after
      page_info[:first_group].last&.id
    end

    memoize def before
      page_info[:before].presence || page_info[:last_group].first&.id
    end

    def pagination_path
      pull_request_review_more_threads_path(
        pull_id: pull_request.number,
        review_id: pull_request_review.id,
        after: after,
        before: before
      )
    end

    memoize def hidden_comment_ids
      pull_request_review.prelude_thread_comment_ids(current_user).join(",")
    end
  end
end
