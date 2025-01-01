# typed: true
# frozen_string_literal: true

require "test_helper"

module PullRequests
  module Copilot
    class CodeReviewCommentTest < GitHub::TestCase
      test "it can have PullRequestReviewComment as its subject type" do
        repo = create(:repository, from_example: :simple)
        pull_request = create(:pull_request, :with_mergeable_head, repository: repo)
        assert_predicate(pull_request, :valid?)

        pull_request_review_comment = create(:pull_request_review_comment, pull_request: pull_request)
        ccr_comment = create(:copilot_code_review_comment, subject: pull_request_review_comment, repository: repo)
        assert_predicate(ccr_comment, :valid?)
      end

      test "it cannot have PullRequestReview as its subject type" do
        repo = create(:repository, from_example: :simple)
        pull_request = create(:pull_request, :with_mergeable_head, repository: repo)
        assert_predicate(pull_request, :valid?)

        pull_request_review = create(:pull_request_review, pull_request: pull_request)
        ccr_comment = build(:copilot_code_review_comment, subject: pull_request_review, repository: repo)
        refute_predicate(ccr_comment, :valid?)
      end

      test "it can be associated with a copilot coding guideline" do
        ccr_comment = create(:copilot_code_review_comment, :with_copilot_coding_guideline)
        assert_predicate(ccr_comment, :valid?)
      end
    end
  end
end
