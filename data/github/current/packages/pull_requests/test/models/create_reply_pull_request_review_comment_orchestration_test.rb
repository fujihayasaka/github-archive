# typed: true
# frozen_string_literal: true

require "test_helper"

class CreateReplyPullRequestReviewCommentOrchestrationTest < GitHub::TestCase
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

  # ------------------------------------------------------------
  #### Comment tests
  # ------------------------------------------------------------

  test "builds a reply comment" do
    orchestrator, _ = execute_orchestrator!(
      body: "Hello world!",
      user: @user,
      stop_after_step: :build_reply
    )

    comment = orchestrator.comment

    refute_nil comment
    assert_equal :started, orchestrator.state.to_sym
    assert_equal "Hello world!", comment.body
    assert_equal @user, comment.user
    assert_equal @repository, comment.repository
    assert_predicate comment, :pending?
    refute_predicate comment, :persisted?
  end

  test "validates body attribute for the comment" do
    PullRequestReviewComment.any_instance.expects(:body).times(3).returns(nil)

    orchestrator, _ = execute_orchestrator!(submit_review: true)
    comment = orchestrator.comment

    assert_equal :skipped, orchestrator.state.to_sym
    assert_equal :validate_reply_comment_attributes_and_relations, orchestrator.step_name&.to_sym
    assert_equal comment.errors.full_messages.first, "Body can't be blank"
    assert_equal orchestrator.error_message, "Failed to create reply: #{comment.errors.full_messages}."
  end


  test "validates state attribute for the comment" do
    PullRequestReviewComment.any_instance.expects(:state).once.returns(nil)

    orchestrator, _ = execute_orchestrator!
    comment = orchestrator.comment

    assert_equal :skipped, orchestrator.state.to_sym
    assert_equal :validate_reply_comment_attributes_and_relations, orchestrator.step_name&.to_sym
    assert_equal comment.errors.full_messages.first, "State does not exist"
    assert_equal orchestrator.error_message, "Failed to create reply: #{comment.errors.full_messages}."
  end

  test "validates bytesize of body attribute for the comment" do
    PullRequestReviewComment.any_instance.expects(:body).times(4).returns("a" * (MYSQL_UNICODE_BLOB_LIMIT + 1))

    orchestrator, _ = execute_orchestrator!(submit_review: true)
    comment = orchestrator.comment

    assert_equal :skipped, orchestrator.state.to_sym
    assert_equal :validate_reply_comment_attributes_and_relations, orchestrator.step_name&.to_sym
    assert_equal comment.errors.full_messages.first, "Body bytesize is larger than MYSQL unicode blob limit"
    assert_equal orchestrator.error_message, "Failed to create reply: #{comment.errors.full_messages}."
  end

  test "calls user_can_interact for the comment" do
    PullRequestReviewComment.any_instance.expects(:user_can_interact).once

    execute_orchestrator!
  end

  test "skips execution if the comment's issue is locked and the commenting user cannot push to the repo" do
    Issue.any_instance.expects(:locked?).once.returns(true)
    if GitHub.enterprise?
      Repository.any_instance.expects(:pushable_by?).with(@user).once.returns(false)
    else
      Repository.any_instance.expects(:pushable_by?).with(@user).twice.returns(false)
    end

    orchestrator, exception = execute_orchestrator!
    comment = orchestrator.comment

    assert_equal :skipped, orchestrator.state.to_sym
    assert_equal :validate_reply_comment_attributes_and_relations, orchestrator.step_name&.to_sym
    assert_equal comment.errors.full_messages.first, "Lock prevents comment"
    assert_equal orchestrator.error_message, "Failed to create reply: #{comment.errors.full_messages}."
  end

  test "fails if the user is not authorized to create content for the comment" do
    auth_obj = ("ContentAuthorizer::RepoAuthorizer").constantize
    ContentAuthorizer.stubs(:authorize).returns(auth_obj)
    auth_obj.stubs(:failed?).returns(true)
    auth_obj.stubs(:error_messages).returns("User unauthorized")

    orchestrator, exception = execute_orchestrator!
    comment = orchestrator.comment

    assert_nil exception
    assert_equal :failed, orchestrator.state.to_sym
    assert_equal :validate_reply_user_authorizations, orchestrator.step_name&.to_sym
    assert_equal comment.errors.full_messages.first, "User unauthorized"
    assert_equal orchestrator.error_message, "Failed to create reply: #{comment.errors.full_messages}."
  end

  test "fails if the comment's user is blocked from reviewing the pull request" do
    PullRequest.any_instance.stubs(:blocked_from_reviewing?).returns(true)

    orchestrator, exception = execute_orchestrator!
    comment = orchestrator.comment

    assert_nil exception
    assert_equal :failed, orchestrator.state.to_sym
    assert_equal :validate_reply_user_authorizations, orchestrator.step_name&.to_sym
    assert_equal comment.errors.full_messages.first, "User is blocked"
    assert_equal orchestrator.error_message, "Failed to create reply: #{comment.errors.full_messages}."
  end

  test "skips execution if the comment does not have a pending review before persistence" do
    @review.expects(:pending?).once.returns(false)

    orchestrator, _ = execute_orchestrator!
    comment = orchestrator.comment

    assert_equal :skipped, orchestrator.state.to_sym
    assert_equal :validate_reply_comment_attributes_and_relations, orchestrator.step_name&.to_sym
    assert_equal comment.errors.full_messages.first, "Pull request review must be pending"
    assert_equal orchestrator.error_message, "Failed to create reply: #{comment.errors.full_messages}."
  end

  test "skips execution if the comment does not have a published review thread or if the review and comment have different authors" do
    orchestrator, _ = execute_orchestrator!(user: @forker)
    comment = orchestrator.comment

    assert_equal :skipped, orchestrator.state.to_sym
    assert_equal :validate_reply_comment_attributes_and_relations, orchestrator.step_name&.to_sym
    assert_equal comment.errors.full_messages.first, "Pull request review thread must be published or must have review with same author as comment"
    assert_equal orchestrator.error_message, "Failed to create reply: #{comment.errors.full_messages}."
  end

  test "instruments failed validation for the comment if the comment fails validation" do
    PullRequestReviewComment.any_instance.expects(:body).times(2).returns(nil)
    PullRequestReviewComment.any_instance.expects(:instrument).with(:validation_failed).once

    orchestrator, _ = execute_orchestrator!(submit_review: true)

    assert_equal :skipped, orchestrator.state.to_sym
  end

  test "saves a reply comment" do
    orchestrator, _ = execute_orchestrator!(stop_after_step: :save_reply)
    comment = orchestrator.comment

    assert_equal :started, orchestrator.state.to_sym
    assert_predicate comment, :persisted?
  end

  ## Replicated from ReviewThreadReplierTest
  test "creates a pending reply comment when single_comment is false" do
    orchestrator, _ = execute_orchestrator!(submit_review: false)
    comment = orchestrator.comment

    assert_equal comment, @parent_comment.replies.first
    assert_equal comment.reply_to_id, @parent_comment.id
    assert_predicate comment, :pending?
  end

  ## Replicated from ReviewThreadReplierTest
  test "creates a submitted reply comment when single_comment is true" do
    orchestrator, _ = execute_orchestrator!(submit_review: true)
    comment = orchestrator.comment

    assert_equal comment, @parent_comment.replies.first
    assert_equal comment.reply_to_id, @parent_comment.id
    assert_predicate comment, :submitted?
  end

  test "instruments the creation of the new comment" do
    GlobalInstrumenter.stubs(:instrument)

    PullRequestReviewComment.any_instance.expects(:instrument).with(
      :create,
    ).once

    GlobalInstrumenter.expects(:instrument).with(
      "pull_request_review_comment.create",
      has_entries(
        actor: @user,
        pull_request: @pull,
        issue: @pull.issue,
        pull_request_creator: @pull.user,
        repository: @repository,
        repository_owner: @user,
        pull_request_review: @review,
      )
    ).once

    execute_orchestrator!(stop_after_step: :instrument_creation_for_comment)
  end

  test "calls subscribe_and_notify for the comment if the comment is not importing" do
    PullRequestReviewComment.any_instance.expects(:importing?).times(4).returns(false)
    PullRequestReviewComment.any_instance.expects(:subscribe_and_notify).once

    execute_orchestrator!(stop_after_step: :subscribe_and_notify_for_comment)
  end

  test "does not call subscribe_and_notify if the comment is not importing" do
    PullRequestReviewComment.any_instance.expects(:importing?).times(4).returns(true)
    PullRequestReviewComment.any_instance.expects(:subscribe_and_notify).never

    execute_orchestrator!(stop_after_step: :subscribe_and_notify_for_comment)
  end

  test "triggers platform subscriptions for the comment" do
    PullRequestReviewComment.any_instance.expects(:trigger_platform_subscriptions).once

    execute_orchestrator!(stop_after_step: :trigger_platform_subscriptions_for_comment)
  end

  test "subscribes to the issue for the comment" do
    PullRequestReviewComment.any_instance.expects(:subscribe_to_issue).once

    execute_orchestrator!
  end

  test "touches a pull request when the comment is a legacy comment" do
    PullRequestReviewComment.any_instance.expects(:legacy_comment?).once.returns(true)
    @pull.expects(:touch).once

    orchestrator, _ = execute_orchestrator!(stop_after_step: :touch_pull_request_after_commit_for_comment)
    comment = orchestrator.comment

    assert_predicate comment, :persisted?
  end

  test "does not touch a pull request when the comment is a legacy comment" do
    PullRequestReviewComment.any_instance.expects(:legacy_comment?).once.returns(false)
    @pull.expects(:touch).never

    orchestrator, _ = execute_orchestrator!(stop_after_step: :touch_pull_request_after_commit_for_comment)
    comment = orchestrator.comment

    assert_predicate comment, :persisted?
  end

  test "notifies the pull request state websocket channel" do
    PullRequest.any_instance.stubs(:requires_review_thread_resolution?).returns(true)

    # invoked by the orchestration in :notify_pull_request_channel
    GitHub::WebSocket.expects(:notify_pull_request_channel).with(@pull, GitHub::WebSocket::Channels.pull_request_state(@pull)).once

    execute_orchestrator!
  end

  # ------------------------------------------------------------
  #### Review tests
  # ------------------------------------------------------------

  test "comments on the review if submit_review is true" do
    now = Time.zone.now.round

    Timecop.freeze(now) do
      orchestrator, _ = execute_orchestrator!(submit_review: true, stop_after_step: :comment_review)
      comment = orchestrator.comment

      assert comment
      assert_equal now, comment.created_at
      assert_equal now, @review.submitted_at
      assert_predicate @review, :commented?
    end
  end

  test "does not comment on the review if submit_review is false" do
    orchestrator, _ = execute_orchestrator!(submit_review: false)
    comment = orchestrator.comment

    assert_nil @review.submitted_at
    assert_predicate @review, :pending?
    assert_predicate comment, :pending?
  end

  test "submits the review's comments if submit_review is true" do
    orchestrator, _ = execute_orchestrator!(submit_review: true)

    comment = orchestrator.comment

    assert comment
    assert_predicate comment, :submitted?
  end

  test "does not submit the review's comments or transition the review if submit_review is false" do
    orchestrator, _ = execute_orchestrator!(submit_review: false)

    comment = orchestrator.comment
    review = orchestrator.public_review

    assert review
    assert comment
    assert_predicate comment, :pending?
    assert_predicate review, :pending?
  end

  test "fulfills a review if submit_review is true and the review satisfies a review request" do
    org = create(:organization, admin: @user)
    org.allow_private_repository_forking(actor: @user)
    @repository.update(owner: org)
    @repository.add_member @forker, action: :write

    review_request = @pull.review_requests.create!(reviewer: @user, deferred: true)

    assert_predicate review_request, :deferred

    orchestrator, _ = execute_orchestrator!(
      submit_review: true,
      stop_after_step: :fulfill_review,
    )

    review = orchestrator.public_review
    review_request_from_orch = review.review_requests.first
    refute_predicate T.must(review_request_from_orch).reload, :deferred
  end

  test "does not fulfill a review if submit_review is false" do
    org = create(:organization, admin: @user)
    org.allow_private_repository_forking(actor: @user)
    @repository.update(owner: org)
    @repository.add_member @forker, action: :write

    review_request = @pull.review_requests.create!(reviewer: @user, deferred: true)

    assert_predicate review_request, :deferred

    orchestrator, _ = execute_orchestrator!(
      submit_review: false,
      stop_after_step: :fulfill_review,
    )

    review_request_from_orch = @pull.review_requests_for(orchestrator.public_review.user).first
    assert_predicate review_request_from_orch.reload, :deferred
  end

  test "increments the pull request's comment counters if submit_review is true" do
    # since the pull request counters have not been updated initially as a result
    # of the test setup / the review hasn't been committed to or transitioned state
    # yet, the comment counters on the pull request will initially be nil. However,
    # since we have two comments that have been persisted, the total counter should
    # change to count the initial comment and the reply
    assert_changes -> { @pull.reload.review_comments_with_body_count }, from: nil, to: 2 do
      orchestrator, _ = execute_orchestrator!(submit_review: true, stop_after_step: :update_pull_request_counters_for_review)
    end
  end

  test "does not include the reply in the pull request's comment counters if submit_review is false" do
    # again, since the pull request counters have not been updated initially as a
    # result of the test setup / the review hasn't been committed to or transitioned
    # state yet, the comment counters on the pull request will initially be nil. Since
    # our reply should be omitted from the total count of comments on the pull request,
    # the total counter should change to count only the initial comment and not the reply

    assert_changes -> { @pull.reload.review_comments_with_body_count }, from: nil, to: 1 do
      orchestrator, _ = execute_orchestrator!(stop_after_step: :update_pull_request_counters_for_review)
    end
  end

  test "instruments a review via the after_commit_review step if submit_review is true"  do
    GlobalInstrumenter.stubs(:instrument)
    GlobalInstrumenter.expects(:instrument).with(
      "pull_request_review_comment.create",
      has_entries(
        actor: @user,
        pull_request: @pull,
        issue: @pull.issue,
        pull_request_creator: @pull.user,
        repository: @repository,
        repository_owner: @user,
        pull_request_review: @review,
      )
    )

    disable_feature_flag(:events_v2_pull_request_review_submitted_enabled)
    disable_feature_flag(:events_v2_pull_request_review_submitted_validation_enabled)
    disable_feature_flag(:events_v2_owner_enabled)

    mock_guid = "be5f4000-b6a0-11ee-8f69-b93ae6629aee"
    Events::Tier1EventPublisher.expects(:new_guid).returns(mock_guid).at_least_once
    expected_flags = Events::Tier1EventPublisher::EventFlags.new(
      webhook_deliveries_enabled: false,
      hookshot_deliveries_enabled: true,
      events_v2_validation_enabled: false,
      publish_tier1_events: false
    )

    @review.expects(:instrument).with(
      :submit,
      has_entries(
        id: @review.id,
        state: 1,
        issue_id: @pull.issue&.id,
        actor: @review.user,
        pull_request_author: @pull.user,
        new_reviewer_was_added: @review.new_reviewer_added?
      )
    ).once

    GlobalInstrumenter.expects(:instrument).with(
      "pull_request_review.submit",
      has_entries(
        review: @review,
        importing: @review.importing?,
        flags: {
          hookshot_deliveries_enabled: true,
          events_v2_validation_enabled: false
        }
      )
    )

    Events::PullRequestReviewPublisher.expects(:submitted).with(@review, event_flags: expected_flags, event_guid: mock_guid).once

    @review.expects(:subscribe_and_notify).once
    @pull.expects(:notify_socket_subscribers).once
    @pull.expects(:synchronize_search_index).once

    execute_orchestrator!(submit_review: true)
  end

  test "instruments a review via the after_commit_review step if submit_review is true and events_v2_pull_request_review_submitted_enabled is true"  do
    GlobalInstrumenter.stubs(:instrument)
    GlobalInstrumenter.expects(:instrument).with(
      "pull_request_review_comment.create",
      has_entries(
        actor: @user,
        pull_request: @pull,
        issue: @pull.issue,
        pull_request_creator: @pull.user,
        repository: @repository,
        repository_owner: @user,
        pull_request_review: @review,
      )
    )

    actor = Events::ParentAsActor.repo_actor(@review.repository.id)
    enable_feature_flag(:events_v2_pull_request_review_submitted_enabled, actor)
    disable_feature_flag(:events_v2_pull_request_review_submitted_validation_enabled)
    enable_feature_flag(:events_v2_owner_enabled, actor)

    mock_guid = "be5f4000-b6a0-11ee-8f69-b93ae6629aee"
    Events::Tier1EventPublisher.expects(:new_guid).returns(mock_guid).at_least_once
    expected_flags = Events::Tier1EventPublisher::EventFlags.new(
      webhook_deliveries_enabled: true,
      hookshot_deliveries_enabled: false,
      events_v2_validation_enabled: false,
      publish_tier1_events: true
    )

    @review.expects(:instrument).with(
      :submit,
      has_entries(
        id: @review.id,
        state: 1,
        issue_id: @pull.issue&.id,
        actor: @review.user,
        pull_request_author: @pull.user,
        new_reviewer_was_added: @review.new_reviewer_added?
      )
    ).once

    GlobalInstrumenter.expects(:instrument).with(
      "pull_request_review.submit",
      has_entries(
        review: @review,
        importing: @review.importing?,
        flags: {
          hookshot_deliveries_enabled: false,
          events_v2_validation_enabled: false
        }
      )
    )

    Events::PullRequestReviewPublisher.expects(:submitted).with(@review, event_flags: expected_flags, event_guid: mock_guid).once

    @review.expects(:subscribe_and_notify).once
    @pull.expects(:notify_socket_subscribers).once
    @pull.expects(:synchronize_search_index).once

    execute_orchestrator!(submit_review: true)
  end

  test "instruments a review via the after_commit_review step if submit_review is true and events_v2_pull_request_review_submitted_validation_enabled is true"  do
    GlobalInstrumenter.stubs(:instrument)
    GlobalInstrumenter.expects(:instrument).with(
      "pull_request_review_comment.create",
      has_entries(
        actor: @user,
        pull_request: @pull,
        issue: @pull.issue,
        pull_request_creator: @pull.user,
        repository: @repository,
        repository_owner: @user,
        pull_request_review: @review,
      )
    )

    actor = Events::ParentAsActor.repo_actor(@review.repository.id)
    disable_feature_flag(:events_v2_pull_request_review_submitted_enabled)
    enable_feature_flag(:events_v2_pull_request_review_submitted_validation_enabled, actor)
    enable_feature_flag(:events_v2_owner_enabled, actor)

    mock_guid = "be5f4000-b6a0-11ee-8f69-b93ae6629aee"
    Events::Tier1EventPublisher.expects(:new_guid).returns(mock_guid).at_least_once
    expected_flags = Events::Tier1EventPublisher::EventFlags.new(
      webhook_deliveries_enabled: false,
      hookshot_deliveries_enabled: true,
      events_v2_validation_enabled: true,
      publish_tier1_events: true
    )

    @review.expects(:instrument).with(
      :submit,
      has_entries(
        id: @review.id,
        state: 1,
        issue_id: @pull.issue&.id,
        actor: @review.user,
        pull_request_author: @pull.user,
        new_reviewer_was_added: @review.new_reviewer_added?
      )
    ).once

    GlobalInstrumenter.expects(:instrument).with(
      "pull_request_review.submit",
      has_entries(
        review: @review,
        importing: @review.importing?,
        flags: {
          hookshot_deliveries_enabled: true,
          events_v2_validation_enabled: true
        }
      )
    )

    Events::PullRequestReviewPublisher.expects(:submitted).with(@review, event_flags: expected_flags, event_guid: mock_guid).once

    @review.expects(:subscribe_and_notify).once
    @pull.expects(:notify_socket_subscribers).once
    @pull.expects(:synchronize_search_index).once

    execute_orchestrator!(submit_review: true)
  end

  private

  # Initialize and execute the PullRequestReviewCommentOrchestration with default values from the test fixtures.
  sig do
    params(
      repository: Repository,
      pull_request: PullRequest,
      review: PullRequestReview,
      thread: PullRequestReviewThread,
      user: User,
      body: String,
      submit_review: T::Boolean,
      stop_after_step: T.nilable(Symbol),
    ).returns([CreateReplyPullRequestReviewCommentOrchestration, T.nilable(Exception)])
  end
  def execute_orchestrator!(
    repository: @repository,
    pull_request: @pull,
    review: @review,
    thread: @parent_comment.pull_request_review_thread,
    user: @user,
    body: "a reply",
    submit_review: false,
    stop_after_step: nil
  )
    if stop_after_step
      CreateReplyPullRequestReviewCommentOrchestration.stop_after_step = stop_after_step
    end

    orchestrator = CreateReplyPullRequestReviewCommentOrchestration.create(
      repository:,
      pull_request:,
      review:,
      thread:,
      user:,
      body:,
      submit_review:,
    )

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
    CreateReplyPullRequestReviewCommentOrchestration.stop_after_step = nil
  end
end
