# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class ReviewCommentBulkCreationCallbacksJobTest < GitHub::TestCase
  include JobTestHelper

  fixtures do
    @owner = create(:user, plan: "micro")
    @forker = create(:user, login: "forker")

    @source = create(:private_repository, owner: @owner, from_example: :review_comment_source)
    @source.add_member @forker, action: :write

    @fork = create(:fork_repository, forker: @forker, fork_repo: @source, from_example: :review_comment_fork)

    @issue = create(:issue, user: @forker, repository: @source)

    @pull = PullRequest.create_for!(@source,
      base: "master",
      head: "#{@fork.user}:topic",
      user: @issue.user,
      issue: @issue
    )

    @review = @pull.reviews.create!(
      user: @owner,
      head_sha: @pull.head_sha,
    )

    @comment = create(:pull_request_review_comment,
      pull_request: @pull,
      user: @owner,
      commit_id: @pull.head_sha,
      path: "aquaman.txt",
      original_position: 21,
      body: "ship it",
      pull_request_review_id: @review.id,
    )

    @review.comment!
  end

  test "calls after_commit_on_create_callbacks for each review comment" do
    enable_feature_flag(:async_pr_review_comment_callbacks)

    events = subscribe "pull_request_review_comment.create"

    ReviewCommentBulkCreationCallbacksJob.perform_now(pull_request_review: @review)

    event = events.pop
    assert_equal event.payload[:comment_id], @comment.id
  end
end
