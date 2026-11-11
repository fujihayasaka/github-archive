# typed: true
# frozen_string_literal: true

# Attaches a comment to an existing pull request review comment thread.
class CreateReplyPullRequestReviewCommentOrchestration < PullRequestReviewCommentOrchestration
  include PullRequests::Orchestrations::DataAttributes

  def only_save_on_orchestration_end? = true
  def skip_pull_request_review_comment_id_validation = true

  data :thread, PullRequestReviewThread
  data :user, User
  data :body, String, persisted: false
  data :submit_review, Types::Boolean
  data :review, PullRequestReview

  # The review comment being created by the Orchestration.
  sig { returns(PullRequestReviewComment) }
  attr_reader :comment

  sig { returns(PullRequestReview) }
  attr_reader :public_review

  sig { returns(PullRequest) }
  def pull_request!
    T.must(pull_request)
  end

  # ------------------------------------------------------------
  #### Comment creation and persistence
  # ------------------------------------------------------------

  step :build_reply do
    @comment = PullRequestReviewComment.new(
      user: user,
      body: body,
      in_reply_to: thread.review_comments.first,
      pull_request: pull_request,
      pull_request_review: review,
      pull_request_review_thread: thread,
      repository: repository,
      thread: thread,
    )
    @public_review = review
    comment.skip_reply_callbacks = true
  end

  # validations that explicitly fail because they represent security concerns
  step :validate_reply_user_authorizations do
    validate_user_can_interact_for_comment
    validate_authorized_to_create_content_for_comment
    validate_creator_is_not_blocked_for_comment

    fail_on_comment_errors
  end

  # validations that return a skipped state
  step :validate_reply_comment_attributes_and_relations do
    validate_attributes_for_comment
    validate_pull_request_lock_for_comment
    validate_review_is_pending_for_comment
    validate_reply_relations_for_comment

    skip_for_comment_validation_failure
  end

  step :save_reply do
    unless comment.save
      comment.errors.add(:base, "Failed to save comment")
    end
    self.pull_request_review_comment = comment

    skip_for_comment_validation_failure
  end

  step :instrument_creation_for_comment do
    comment.instrument_creation

    fail_on_comment_errors
  end

  step :subscribe_and_notify_for_comment do
    return if comment.importing?

    comment.subscribe_and_notify

    fail_on_comment_errors
  end

  step :trigger_platform_subscriptions_for_comment do
    comment.public_trigger_platform_subscriptions

    fail_on_comment_errors
  end

  # Touching a pull request is needed to kick off indexing the pull request for
  # search. This should in theory be the last hook called on the pull request
  # review comment model. We explicitly return and refrain from touching the
  # pull request model in the event that the comment isn't a legacy comment since
  # we do not need to re-index when the comment is pending or associated to a
  # pending review.
  step :touch_pull_request_after_commit_for_comment do
    return unless comment.legacy_comment?

    pull_request!.touch
  end

  # ------------------------------------------------------------
  #### Review state transition
  # ------------------------------------------------------------

  step :set_skip_callbacks_for_review do
    review.skip_review_callbacks = true
  end

  step :comment_review do
    if submit_review
      review.submitted_at = Time.zone.now
      review.comment!
    end
  end

  step :submit_review_comments do
    return unless submit_review

    GitHub.dogstats.time("pull_request_review.after_submission") do
      return false unless valid?

      pending_comments = review.review_comments.with_pending_state
      GitHub::PrefillAssociations.prefill_associations(pending_comments, :pull_request, available_records: [pull_request])
      GitHub::PrefillAssociations.prefill_associations(pending_comments, [:user, :pull_request_review_thread, :repository])
      pending_comments.each(&:submit!)

    end
  end

  step :fulfill_review do
    return unless submit_review
    return unless review.satisfies_request?

    fullfilled_team_requests = pull_request!.team_requests_on_behalf_of(review.user)

    return unless fullfilled_team_requests.any? || pull_request!.review_requested_for?(review.user)

    pending_requests = pull_request!.review_requests_for(review.user)
    pending_or_fulfilled_requests = [fullfilled_team_requests, pending_requests].compact.reduce([], :|)
    review.review_requests = pending_or_fulfilled_requests
    ReviewRequest.where(id: pending_or_fulfilled_requests.map(&:id)).update_all(deferred: false)
  end

  step :update_pull_request_counters_for_review do
    pull_request!.update_review_and_comment_counts
  end

  step :after_commit_review do
    return unless submit_review

    event_guid = Events::Tier1EventPublisher.new_guid(Time.now)
    event_flags = Events::Tier1EventPublisher.calculate_event_flags(
      event_type: :pull_request_review,
      event_action: :submitted,
      target_repository_id: T.must(review.repository).id,
      target_organization_id: T.must(review.repository).organization_id
    )

    payload = {
      id: review.id,
      state: review.reload.state,
      issue_id: comment.issue.id,
      actor: review.user,
      pull_request_author: pull_request!.user,
      new_reviewer_was_added: review.new_reviewer_added?,
      event_guid: event_guid,
      flags: event_flags.instrumentation_flags,
    }
    review.instrument(:submit, payload)
    GlobalInstrumenter.instrument("pull_request_review.submit", review: review, importing: review.importing?)
    Events::PullRequestReviewPublisher.submitted(review, event_flags: event_flags, event_guid: event_guid)

    submitted_comments = review.review_comments.with_submitted_state
    GitHub::PrefillAssociations.prefill_associations(submitted_comments, :pull_request, available_records: [pull_request])
    submitted_comments.each { |review_comment| review_comment.allowed = review.allowed? }
    submitted_comments.each(&:instrument_submission)

    review.subscribe_and_notify unless review.importing?
    pull_request!.notify_socket_subscribers
    pull_request!.synchronize_search_index

    if review.state_previously_changed? && review.current_state > :commented
      review.notify_state_changed
      review.trigger_review_decision_updated
    end
  end

  step :reload_comment do
    comment.reload
  end

  step :notify_pull_request_channel do
    if pull_request!.requires_review_thread_resolution?
      channel = GitHub::WebSocket::Channels.pull_request_state(pull_request)
      GitHub::WebSocket.notify_pull_request_channel(pull_request, channel)
    end
  end

  # Steps called after job_start run asynchronously.
  # Adding steps with new names after job_start may cause invalid step name
  # orchestration errors.
  # When migrating synchronous steps to run asynchronously, it is recommended to
  # rename the existing step rather than adding a new step after job_start:

  # step :temporary_renamed_X
  # job_start
  # step :X

  job_start

  step :subscribe_to_issue_for_comment do
    self.pull_request_review_comment&.subscribe_to_issue
  end

  private

  sig { returns(StepTuple) }
  def skip_for_comment_validation_failure
    if comment.errors.any?
      # When skipping an orchestration, no error is raised and adding errors to
      # the base orchestration class doesn't cause them to be available to code
      # executing the orchestration itself (at least under test). The message
      # passed as the second argument to the explicit `return` is, however,
      # persisted in the error_message column on the orchestration record itself

      comment.instrument(:validation_failed)
      # rubocop:disable Style/RedundantReturn
      return :skipped, "Failed to create reply: #{comment.errors.full_messages}."
    end
  end

  sig { returns(StepTuple) }
  def fail_on_comment_errors
    if comment.errors.any?
      errors.add(:base, "Comment errors: #{comment.errors.full_messages}.")
      comment.instrument(:validation_failed)
      # rubocop:disable Style/RedundantReturn
      return :failed, "Failed to create reply: #{comment.errors.full_messages}."
    end
  end

  sig { returns(StepTuple) }
  def validate_user_can_interact_for_comment
    comment.user_can_interact
  end

  sig { void }
  def validate_authorized_to_create_content_for_comment
    authorization = ContentAuthorizer.authorize(
      comment.modifying_user,
      :pull_request_comment,
      :create,
      issue: comment.issue,
      repo: comment.repository
    )

    if authorization.failed?
      comment.errors.add(:base, authorization.error_messages)
    end
  end

  sig { void }
  def validate_creator_is_not_blocked_for_comment
    if comment.pull_request&.blocked_from_reviewing?(comment.user)
      comment.errors.add(:user, "is blocked")
    end
  end

  sig { void }
  def validate_attributes_for_comment
    unless comment.body.present?
      comment.errors.add(:body, "can't be blank")
    end

    unless comment.state.present?
      comment.errors.add(:state, "does not exist")
    end

    if comment.body && comment.body.bytesize > MYSQL_UNICODE_BLOB_LIMIT
      comment.errors.add(:body, "bytesize is larger than MYSQL unicode blob limit")
    end
  end

  sig { void }
  def validate_pull_request_lock_for_comment
    return unless comment.pull_request&.issue&.locked?
    return if comment.pull_request&.repository&.pushable_by?(comment.user)

    comment.errors.add(:base, "Lock prevents comment")
  end

  sig { void }
  def validate_review_is_pending_for_comment
    unless comment.pull_request_review&.pending?
      comment.errors.add(:pull_request_review_id, "must be pending")
    end
  end

  sig { void }
  def validate_reply_relations_for_comment
    return unless comment.pull_request_review

    return if comment.thread.published?

    same_author = comment.user_id == comment.pull_request_review&.user_id
    return if same_author

    messages = []
    messages << "must be published" unless comment.thread.published?
    messages << "must have review with same author as comment" unless same_author

    comment.errors.add(:pull_request_review_thread_id, messages.join(" or "))
  end
end
