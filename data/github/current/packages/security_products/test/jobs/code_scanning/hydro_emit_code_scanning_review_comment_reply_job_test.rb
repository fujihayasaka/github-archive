# typed: true
# frozen_string_literal: true

require "test_helper"

class CodeScanning::HydroEmitCodeScanningReviewCommentReplyJobTest < GitHub::TestCase
  skip_enterprise

  include HydroMessageJobTestHelpers
  include HydroTestHelpers

  fixtures do
    @user = create :user, login: "octocat"
    @repo = create :private_repository, owner: @user, name: "Hello-World", from_example: :pull_request_fork

    @pull = PullRequest.create_for @repo,
      user: @user,
      base: "master",
      head: "topic",
      title: "some title",
      body: "some body"

    make_trusted_oauth_apps_owner
    @code_scanning_integration = create(:code_scanning_integration)
  end

  test "hydro event emitted for reply to message by GHAS bot, and a reply to that reply" do
    review_thread = PullRequestReviewThread.new(
      path: "README.md",
      position: 42,
      pull_request: @pull,
      repository: @repo,
    )

    diff = @pull.async_diff(end_commit_oid: @pull.head_sha).sync
    path = diff.deltas.first.path.dup
    bot_comment = review_thread.build_first_diff_position_comment(
      user: @code_scanning_integration.bot,
      body: "New Code Scanning alert",
      diff: diff,
      position: 1,
      path: path,
    ).tap(&:save)

    review_thread.save!

    first_reply_comment = PullRequestReviewComment.new(
      repository: @repo,
      pull_request: @pull,
      pull_request_review_thread: review_thread,
      body: "Reply to GHAS bot comment",
      reply_to_id: bot_comment.id,
      user: @user,
    )
    first_reply_comment.save!

    message = hydro_message_for_comment(first_reply_comment)
    perform_hydro_message_job(message, schema: "github.v1.PullRequestReviewCommentCreate", queue: "code_scanning_hydro_emit_code_scanning_review_comment_reply")

    assert_hydro_published(
      message,
      schema: "github.v1.PullRequestReviewCommentCreate",
      topic: "code_scanning.v0.CodeScanningReviewCommentReply"
    )

    second_reply_comment = PullRequestReviewComment.new(
      repository: @repo,
      pull_request: @pull,
      pull_request_review_thread: review_thread,
      body: "Additional reply to GHAS bot comment",
      reply_to_id: first_reply_comment.id,
      user: @user,
    )
    second_reply_comment.save!

    message = hydro_message_for_comment(second_reply_comment)
    perform_hydro_message_job(message, schema: "github.v1.PullRequestReviewCommentCreate", queue: "code_scanning_hydro_emit_code_scanning_review_comment_reply")

    assert_hydro_published(
      message,
      schema: "github.v1.PullRequestReviewCommentCreate",
      topic: "code_scanning.v0.CodeScanningReviewCommentReply"
    )
  end

  test "no hydro event if it's not a reply" do
    review_thread = PullRequestReviewThread.new(
      path: "README.md",
      position: 42,
      pull_request: @pull,
      repository: @repo,
    )

    diff = @pull.async_diff(end_commit_oid: @pull.head_sha).sync
    path = diff.deltas.first.path.dup
    sole_comment = review_thread.build_first_diff_position_comment(
      user: create(:user),
      body: "Nice work!",
      diff: diff,
      position: 1,
      path: path,
    ).tap(&:save)

    review_thread.save!

    message = hydro_message_for_comment(sole_comment)

    perform_hydro_message_job(message, schema: "github.v1.PullRequestReviewCommentCreate", queue: "code_scanning_hydro_emit_code_scanning_review_comment_reply")

    refute_hydro_messages(
      schema: "github.v1.PullRequestReviewCommentCreate",
      topic: "code_scanning.v0.CodeScanningReviewCommentReply"
    )
  end

  test "no hydro event for reply to message by someone else" do
    review_thread = PullRequestReviewThread.new(
      path: "README.md",
      position: 42,
      pull_request: @pull,
      repository: @repo,
    )

    diff = @pull.async_diff(end_commit_oid: @pull.head_sha).sync
    path = diff.deltas.first.path.dup
    initial_comment = review_thread.build_first_diff_position_comment(
      user: create(:user),
      body: "Nice work!",
      diff: diff,
      position: 1,
      path: path,
    ).tap(&:save)

    review_thread.save!

    reply_comment = PullRequestReviewComment.new(
      repository: @repo,
      pull_request: @pull,
      pull_request_review_thread: review_thread,
      body: "Reply to regular comment",
      reply_to_id: initial_comment.id,
      user: @user,
    )
    reply_comment.save!

    message = hydro_message_for_comment(reply_comment)

    perform_hydro_message_job(message, schema: "github.v1.PullRequestReviewCommentCreate", queue: "code_scanning_hydro_emit_code_scanning_review_comment_reply")

    refute_hydro_messages(
      schema: "github.v1.PullRequestReviewCommentCreate",
      topic: "code_scanning.v0.CodeScanningReviewCommentReply"
    )
  end

  sig { params(comment: PullRequestReviewComment).returns(T::Hash[Symbol, T.untyped]) }
  def hydro_message_for_comment(comment)
    {
      actor: Hydro::EntitySerializer.user(comment.user),
      repository: Hydro::EntitySerializer.repository(comment.repository),
      repository_owner: Hydro::EntitySerializer.user(T.must(comment.repository).owner),
      issue: Hydro::EntitySerializer.issue(comment.issue),
      pull_request: Hydro::EntitySerializer.pull_request(comment.pull_request),
      pull_request_review_comment: Hydro::EntitySerializer.pull_request_review_comment(comment),
      pull_request_review_thread: Hydro::EntitySerializer.pull_request_review_thread(comment.pull_request_review_thread),
    }
  end
end
