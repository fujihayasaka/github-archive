# typed: true
# frozen_string_literal: true

require "test_helper"

class DeletePullRequestReviewCommentOrchestrationTest < GitHub::TestCase
  fixtures do
    @user = create(:user, login: "mona")
    @repo = create(:repository, owner: @user, from_example: :review_comment_source)
    @forker = create(:user, login: "bwalsh")
    forked = create(:fork_repository, forker: @forker, fork_repo: @repo, from_example: :review_comment_fork)
    @repo.add_member @forker

    issue = create(:issue, user: @forker, repository: @repo)
    @pull = create(:pull_request,
      repository: @repo,
      base_repository: @repo,
      base_user: @repo.owner,
      base_ref: "master",
      head_repository: forked,
      head_user: forked.owner,
      head_ref: "topic",
      issue: issue,
      user: @forker,
    )
    issue.pull_request = @pull
    @review = @pull.reviews.create!(
      user: @user,
      head_sha: @pull.head_sha,
    )
    @comment = create(:pull_request_review_comment, pull_request: @pull,
      user: @user, body: "hiya",
      commit_id: @pull.head_sha,
      path: "aquaman.txt",
      original_position: 26,
      pull_request_review: @review
    )
    @review.comment!
  end

  test "skips orchestration execution if a comment cannot be deleted" do
    @comment.stubs(:code_scanning?).returns(true)

    orchestrator, _ = execute_orchestrator!(comment: @comment)

    assert_equal orchestrator.state, "skipped"
    assert_equal orchestrator.error_message, "Failed to delete comment: #{@comment.errors.full_messages}."
    assert_equal @comment.errors.first.message, "Comment cannot be deleted during code scanning."
  end

  test "generates a webhook payload" do
    Hook::DeliverySystem.any_instance.expects(:generate_hookshot_payloads).once

    orchestrator, _ = execute_orchestrator!(stop_after_step: :generate_webhook_payloads)
    assert !orchestrator.delivery_system.nil?
    assert_instance_of(Hook::DeliverySystem, orchestrator.delivery_system)
  end

  test "queues a webhook payload for delivery" do
    Hook::DeliverySystem.any_instance.expects(:deliver_later).once

    orchestrator, _ = execute_orchestrator!(stop_after_step: :queue_webhook_delivery)
    assert_instance_of(Hook::DeliverySystem, orchestrator.delivery_system)
  end

  test "does not queue a webhook delivery if the user is spammy" do
    @comment.update_column(:user_hidden, 1)

    Hook::DeliverySystem.any_instance.expects(:deliver_later).never

    orchestrator, _ = execute_orchestrator!(comment: @comment)
    assert_nil orchestrator.delivery_system
  end

  test "generates an issue event" do
    orchestrator, _ = execute_orchestrator!(actor: @forker)
    assert_equal @comment.issue.events.last.event, "comment_deleted"
  end

  test "deletes a given comment" do
    orchestrator, _ = execute_orchestrator!
    assert_equal :succeeded, orchestrator.reload.state.to_sym
    assert_nil PullRequestReviewComment.find_by(id: @comment.id)
  end

  test "instruments deletion" do
    GlobalInstrumenter.stubs(:instrument)
    GlobalInstrumenter.expects(:instrument).with(
      "pull_request_review_comment.delete",
      has_entries(
        actor: @comment.user,
        pull_request: @pull,
        repository: @repo,
        review_comment: @comment,
        pull_request_review: @comment.pull_request_review,
        pull_request_review_thread: @comment.pull_request_review_thread,
      ),
    )

    @comment.expects(:instrument).with(
      :delete,
      repo: @repo,
      actor: @comment.modifying_user,
      author: @comment.user
    )

    orchestrator, _ = execute_orchestrator!(comment: @comment)
  end

  test "cleans up review and review thread" do
    review_thread_id = @comment.pull_request_review_thread.id

    orchestrator, _ = execute_orchestrator!
    assert_nil PullRequestReview.find_by(id: @review.id)
    assert_nil PullRequestReviewThread.find_by(id: review_thread_id)
  end

  test "unresolves thread if not conversation" do
    make_trusted_oauth_apps_owner
    create(:code_scanning_integration)

    @comment.pull_request_review_thread.stubs(:resolved?).returns(true)
    @comment.pull_request_review_thread.stubs(:conversation?).returns(false)

    @comment.pull_request_review_thread.expects(:unresolve).with(unresolver: Apps::Internal.integration(:code_scanning).bot)

    orchestrator, _ = execute_orchestrator!(comment: @comment)
  end

  test "reparents replies" do
    new_parent_comment = create(:pull_request_review_comment,
      pull_request: @pull,
      user: @user,
      body: "hiya",
      commit_id: @pull.head_sha,
      path: "aquaman.txt",
      original_position: 27,
      reply_to_id: @comment.id)
    comment_to_reparent = create(:pull_request_review_comment,
      pull_request: @pull,
      user: @user,
      body: "hiyaaaa",
      commit_id: @pull.head_sha,
      path: "aquaman.txt",
      original_position: 27,
      reply_to_id: @comment.id)

    orchestrator, _ = execute_orchestrator!

    new_parent_comment.reload
    comment_to_reparent.reload

    assert_nil new_parent_comment.reply_to_id
    assert_equal comment_to_reparent.reply_to_id, new_parent_comment.id
  end

  test "updates pull request counters" do
    assert_equal 1, @pull.review_comments_with_body_count

    review = @pull.reviews.create!(
      user: @user,
      head_sha: @pull.head_sha,
    )
    # creating a second comment outside of the fixture block upon
    # which to invoke the orchestration so that the comment's
    # state is included in its previous changes
    second_comment = create(:pull_request_review_comment, pull_request: @pull,
      user: @user, body: "second comment",
      commit_id: @pull.head_sha,
      path: "aquaman.txt",
      original_position: 24,
      pull_request_review: review
    )
    review.comment!

    assert_equal 2, @pull.reload.review_comments_with_body_count

    GitHub.flipper[:pull_request_sub_triggers].enable

    platform_schema_mock = Minitest::Mock.new(Platform::Schema)
    platform_schema_mock.expects(:trigger).once.with(
      :pull_request_comments_updated,
      { id: @pull.global_relay_id }
    )
    Platform::Schema.expects(:subscriptions).returns(platform_schema_mock).once

    orchestration, _ = execute_orchestrator!(comment: second_comment.reload)

    @pull.reload
    assert_equal 1, @pull.review_comments_with_body_count
  end

  test "touches pull request after commit" do
    start_time = @pull.updated_at

    orchestration, _ = execute_orchestrator!

    @pull.reload
    assert start_time < @pull.updated_at
  end

  test "notifies the pull request state websocket channel" do
    PullRequest.any_instance.stubs(:requires_review_thread_resolution?).returns(true)

    # invoked by PR after_commit method #notify_socket_subscribers
    # once when @pull is created in setup block, once more when
    # @pull is touched by orchestration, and finally invoked by the
    # orchestration via the :notify_pull_request_channel step
    GitHub::WebSocket.expects(:notify_pull_request_channel).times(3)

    orchestration, _ = execute_orchestrator!(pull_request: @pull)
  end

  sig do
    params(
      repository: Repository,
      pull_request: PullRequest,
      actor: User,
      comment: PullRequestReviewComment,
      stop_after_step: T.nilable(Symbol)
    ).returns([DeletePullRequestReviewCommentOrchestration, T.nilable(Exception)])
  end
  def execute_orchestrator!(
    repository: @repo,
    pull_request: @pull,
    actor: @user,
    comment: @comment,
    stop_after_step: nil
  )
    if stop_after_step
      DeletePullRequestReviewCommentOrchestration.stop_after_step = stop_after_step
    end

    # the repository and pull request need to be the same as the ones that
    # are associationed to the thread and comment created by the orchestration
    # in order for the orchestration's own database queries and persistence
    # to work
    orchestrator_args = {
      repository:,
      pull_request:,
      pull_request_review_comment: comment,
      actor: actor,
      comment_user: comment.user
    }

    orchestrator = DeletePullRequestReviewCommentOrchestration.create(orchestrator_args)
    exception = T.let(nil, T.nilable(Exception))

    perform_enqueued_jobs(only: [PullRequestOrchestrationJob]) do
      begin
        orchestrator.execute!
      rescue Orchestration::Error => e
        exception = e
      end
    end

    [orchestrator.tap(&:reload), exception]
  ensure
    DeletePullRequestReviewCommentOrchestration.stop_after_step = nil
  end
end
