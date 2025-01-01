# typed: true
# frozen_string_literal: true

require "test_helper"

class ReviewThreadCreatorTest < GitHub::TestCase
  include PullRequestSynchronizationTestHelpers

  fixtures do
    Spokesd.enable_spokesd

    @user = create(:user)
    @repo = create(:repository, owner: @user, from_example: :review_comment_fork)

    issue = create(:issue, repository: @repo)
    @pull = PullRequest.create_for(@repo,
      base: "master",
      head: "topic",
      user: @user,
      issue: issue,
    )
    example_repo_snapshot
  end

  setup do
    example_repo_restore
  end

  test "creates a thread and submits a comment when submit_review is true" do
    args = thread_and_comment_args
    thread, comment = ReviewThreadCreator.new(**args).create_thread

    assert_predicate thread, :persisted?
    assert_predicate comment, :persisted?
    review = comment.pull_request_review
    assert_predicate review, :commented?
    assert_predicate comment.reload, :submitted?
  end

  test "creates a thread and a pending review when submit_review is false" do
    args = thread_and_comment_args(submit_review: false)
    thread, comment = ReviewThreadCreator.new(**args).create_thread

    assert_predicate thread, :persisted?
    assert_predicate comment, :persisted?
    review = comment.pull_request_review
    assert_predicate review, :pending?
    assert_predicate comment.reload, :pending?
  end

  test "creates a multi-line comment" do
    args = thread_and_comment_args(line: 27, side: "right", start_line: 25, start_side: "right")
    thread, comment = ReviewThreadCreator.new(**args).create_thread

    assert_predicate thread, :persisted?
    assert_predicate comment, :persisted?
    assert comment.reload.start_position_offset
  end

  test "creates a comment on a deletion" do
    args = thread_and_comment_args(line: 18, side: "left")
    thread, comment = ReviewThreadCreator.new(**args).create_thread

    assert_predicate thread, :persisted?
    assert_predicate comment, :persisted?
    assert_predicate thread, :left_blob?
  end

  test "returns thread with errors for bad data" do
    args = thread_and_comment_args(line: 100)
    thread, comment = ReviewThreadCreator.new(**args).create_thread

    refute_predicate thread, :persisted?
    refute_predicate comment, :persisted?
    assert_includes thread.errors.full_messages, "Line must be part of the diff"
  end

  test "marks comments outdated on creation" do
    # TODO: the creation_diff logic is broken and we don't properly mark comments
    # as outdated on creation with this feature flag on so this needs to be
    # revisited if we ever ship comment outside the diff
    GitHub.flipper[:comment_outside_the_diff].disable

    base_ref = @repo.heads.find("master")
    head_ref = @repo.heads.create("suggestion-topic", base_ref.target, @repo.owner)

    head_ref.append_commit({
      message: "a change",
      committer: @repo.owner,
    }, @repo.owner) do |files|
      files.add("README.txt", "```\ncode\n```\n")
    end

    pull = create(:pull_request,
      repository: @repo,
      base_repository: @repo,
      base_user: @repo.owner,
      base_ref: "master",
      head_repository: @repo,
      head_user: @repo.owner,
      head_ref: "suggestion-topic",
      user: @repo.owner,
    )
    sha_before = pull.head_sha

    with_enqueued_pr_sync_jobs do
      head_ref.append_commit({
        message: "a change",
        committer: @repo.owner,
      }, @repo.owner) do |files|
        files.add("README.txt", "```erlang\ncode\n```\n")
      end
    end
    pull.reload
    review = pull.pending_review_for(user: pull.user, head_sha: sha_before)
    args = {
      author: pull.user,
      path: "README.txt",
      body: "```suggestion\r\n```erlang\r\n```",
      line: 1,
      side: "right",
      submit_review: true,
      review: review,
      pull: pull,
      diff_range: {
        end_commit_oid: sha_before,
        start_commit_oid: pull.base_sha,
        base_commit_oid: pull.base_sha
      }
    }
    thread, comment = ReviewThreadCreator.new(**args).create_thread
    assert thread.outdated
  end

  test "creates a thread when supplied with an file subject type" do
    args = thread_and_comment_args(subject_type: "file")
    thread, comment = ReviewThreadCreator.new(**args).create_thread

    assert_predicate thread, :persisted?
    assert_predicate comment, :persisted?
    assert_equal thread.subject_type, "file"
  end

  test "creates a thread when supplied with an file subject type and a nil line parameter" do
    args = thread_and_comment_args(subject_type: "file", line: nil)
    thread, comment = ReviewThreadCreator.new(**args).create_thread

    assert_predicate thread, :persisted?
    assert_predicate comment, :persisted?
    assert_equal thread.subject_type, "file"
  end

  def thread_and_comment_args(overrides = {})
    pull_comparison = PullRequest::Comparison.find(pull: @pull,
      start_commit_oid: @pull.merge_base,
      end_commit_oid: @pull.head_sha,
      base_commit_oid: @pull.merge_base
    )
    {
      author: @user,
      review: @pull.pending_review_for(user: @user),
      body: "that is some cool code",
      path: "aquaman.txt",
      line: 15,
      side: "right",
      subject_type: "line",
      submit_review: true,
      diff_range: {
        comparison_start_oid: pull_comparison.start_commit.oid,
        comparison_end_oid: pull_comparison.end_commit.oid,
        comparison_base_oid: pull_comparison.base_commit.oid,
      }
    }.merge(overrides)
  end
end
