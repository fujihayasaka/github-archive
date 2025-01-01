# typed: true
# frozen_string_literal: true

require "test_helper"

class ReviewThreadReplierTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    repo = create(:repository, owner: @user, from_example: :review_comment_fork)

    issue = create(:issue, repository: repo)
    @pull = PullRequest.create_for(repo,
      base: "master",
      head: "topic",
      user: @user,
      issue: issue,
    )
    @thread = @pull.review_threads.create(
      commit_id: @pull.head_sha,
      path: "aquaman.txt",
      original_position: 26,
    )
    @parent_comment = create(:pull_request_review_comment,
      pull_request_review_thread: @thread,
      pull_request: @pull,
      user: @user,
      body: "Hello world",
    )
  end

  test "creates a pending reply comment when submit_review is false" do
    args = comment_reply_args
    comment = ReviewThreadReplier.new(**args).create_reply_comment

    assert_predicate comment, :persisted?
    assert_predicate comment.reload, :pending?
    assert_equal comment.reply_to_id, @parent_comment.id
  end

  test "creates a submitted reply comment when submit_review is true" do
    args = comment_reply_args(single_comment: true)
    comment = ReviewThreadReplier.new(**args).create_reply_comment

    assert_predicate comment, :persisted?
    assert_predicate comment.reload, :submitted?
    assert_equal comment.reply_to_id, @parent_comment.id
  end

  test "reports an error if review missing" do
    args = comment_reply_args(review: nil)
    assert_raises(ReviewThreadReplier::PullRequestReviewMissingError) do
      ReviewThreadReplier.new(**args).create_reply_comment
    end
  end

  def comment_reply_args(overrides = {})
    {
      review: @pull.pending_review_for(user: @user),
      parent: @parent_comment,
      body: "This is a comment reply",
      user: @user,
      single_comment: false,
    }.merge(overrides)
  end
end
