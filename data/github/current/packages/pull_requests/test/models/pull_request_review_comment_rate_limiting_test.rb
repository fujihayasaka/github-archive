# encoding: utf-8
# typed: true
# frozen_string_literal: true

require "test_helper"

require "test_helpers/pull_requests"

class PullRequestReviewCommentRateLimitingTest < GitHub::TestCase
  def create_comment(pull, user)
    create(:pull_request_review_comment,
      pull_request: pull,
      user: user,
      body: "YeeAaAaa",
      path: "aquaman.txt",
      original_position: 26,
      commit_id: pull.head_sha)
  end

  setup_once do
    enable_cache_storage
  end

  setup do
    enable_content_creation_rate_limiting
    reset_cache
  end

  teardown_once do
    disable_cache_storage
  end

  fixtures do
    @source = create(:repository, from_example: :review_comment_source)
    @issue = create(:issue, user: @source.owner, repository: @source)
    @fork = create(:fork_repository, forker: (create :user), fork_repo: @source, from_example: :review_comment_fork)
    @pull =
      create(:pull_request,
        repository: @source,
        base_repository: @source,
        base_user: @source.owner,
        base_ref: "master",
        head_repository: @fork,
        head_user: @fork.owner,
        head_ref: "topic",
        issue: @issue,
        user: @fork.owner,
      )
  end

  test "comments are rate limited" do
    user = create(:user)
    5.times do |_i|
      comment = create_comment(@pull, user)
      assert_empty comment.errors
    end

    begin
      create_comment(@pull, user)
    rescue ActiveRecord::RecordInvalid => e
      assert_match "submitted too quickly", e.message
    end
  end
end
