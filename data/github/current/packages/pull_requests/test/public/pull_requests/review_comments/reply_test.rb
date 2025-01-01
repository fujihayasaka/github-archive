# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequestReviewCommentsReplyTest < GitHub::TestCase
  fixtures do
    @user = create(:user, login: "mona")
    @forker = create(:user, login: "bwalsh")

    @repository = create(:repository, owner: @user, from_example: :review_comment_source)
    @repository.add_member(@forker)

    @fork = create(:fork_repository, forker: @forker, fork_repo: @repository, from_example: :review_comment_fork)

    @pull = PullRequest.create_for!(@repository, {
      user: @forker,
      base: @repository.default_branch,
      head: "#{@forker}:topic",
      title: "Fix typo",
      body: "This is a typo fix, please merge ASAP!"
    })

    @review = @pull.reviews.create!(
      user: @user,
      head_sha: @pull.head_sha,
    )

    # TODO: Replace this with PullRequests::ReviewComments::Create
    @parent_comment = create(:pull_request_review_comment, pull_request: @pull,
      user: @user, body: "hiya",
      commit_id: @pull.head_sha,
      path: "aquaman.txt",
      original_position: 26,
      pull_request_review: @review,
      pull_request_review_thread: create(:pull_request_review_thread, pull_request: @pull, repository: @repository),
    )

    @parent_comment.submit!
  end

  test "it can successfully append a reply to a thread without submitting a review" do
    result = PullRequests::ReviewComments::Reply.create(
      repository: @repository,
      pull_request: @pull,
      review: @review,
      thread: @parent_comment.pull_request_review_thread,
      user: @user,
      body: "A reply to this conversation",
      submit_review: false
    )

    if result.is_a?(PullRequests::ReviewComments::Reply::Error)
      fail "Should have succeeded, but didn't: #{result.inspect}"
    end

    comment = result.comment

    assert_equal "pending", comment.state, "The comment should not have submitted."
    assert_equal :pending, @review.current_state.name, "The review should not have been submitted."
    assert_equal "A reply to this conversation", comment.body
    assert_equal @user, comment.user
    assert_equal @pull, comment.pull_request
    assert_equal @review, comment.pull_request_review
    assert_includes @parent_comment.replies, comment
  end

  test "it can successfuly append a reply and submit a review" do
    result = PullRequests::ReviewComments::Reply.create(
      repository: @repository,
      pull_request: @pull,
      review: @review,
      thread: @parent_comment.pull_request_review_thread,
      user: @user,
      body: "A reply to this conversation",
      submit_review: true
    )

    if result.is_a?(PullRequests::ReviewComments::Reply::Error)
      fail "Should have succeeded, but didn't: #{result.inspect}"
    end

    assert_equal "submitted", result.comment.state
    assert_equal :commented, @review.current_state.name
  end

  test "it returns an error upon failing to execute" do
    result = PullRequests::ReviewComments::Reply.create(
      repository: @repository,
      pull_request: @pull,
      review: @review,
      thread: @parent_comment.pull_request_review_thread,
      user: @user,
      body: "",
      submit_review: true
    )

    if result.is_a?(PullRequests::ReviewComments::Reply::Success)
      fail "Should have errored, but didn't: #{result.inspect}"
    end

    assert_includes result.errors.full_messages.join, "Body can't be blank"
  end
end
