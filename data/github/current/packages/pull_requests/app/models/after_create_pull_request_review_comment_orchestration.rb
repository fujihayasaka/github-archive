# typed: true
# frozen_string_literal: true

class AfterCreatePullRequestReviewCommentOrchestration < PullRequestReviewCommentOrchestration
  include PullRequests::Orchestrations::DataAttributes
  include GitHub::Memoizer

  data :actor, User
  data :importing, Types::Boolean, default: false, required: false
  data :review_submitted, Types::Boolean, default: false, required: false # Was the review submitted?
  data :new_reviewer_was_added, Types::Boolean, default: false, required: false
  data :position_is_used, Types::Boolean, default: false, required: false

  job_start

  step :instrument_creation_for_comment do
    comment.position_is_used = position_is_used
    comment.instrument_creation
  end

  step :instrument_creation_for_thread do
    thread.instrument(:create)

    GlobalInstrumenter.instrument("pull_request_review_thread.create", {
      pull_request_review_thread: thread,
      repository:,
    })
  end

  step :submit_each_comment do
    return unless review_submitted

    GitHub.dogstats.time("pull_request_review.after_submission") do
      pending_comments = review.review_comments.with_pending_state
      GitHub::PrefillAssociations.prefill_associations(pending_comments, :pull_request, available_records: [pull])
      GitHub::PrefillAssociations.prefill_associations(pending_comments, [:user, :pull_request_review_thread, :repository])
      pending_comments.each(&:submit!)
    end
  end

  step :fulfill_review do
    return unless review_submitted
    return unless review.satisfies_request?

    fullfilled_team_requests = pull.team_requests_on_behalf_of(review.user)

    return unless fullfilled_team_requests.any? || pull.review_requested_for?(review.user)

    pending_or_fulfilled_requests = [
      fullfilled_team_requests,
      pull.review_requests_for(review.user)
    ].compact.reduce([], :|)

    review.review_requests = pending_or_fulfilled_requests

    ReviewRequest.where(
      id: pending_or_fulfilled_requests.map(&:id)
    ).update_all(deferred: false)
  end

  step :update_pull_request_counters_for_review do
    pull.update_review_and_comment_counts
  end

  # TODO: Split these steps up into logical groupings.
  step :after_commit_review do
    return unless review_submitted
    return unless issue = pull.issue

    event_guid = Events::Tier1EventPublisher.new_guid(Time.now)

    payload = {
      id: review.id,
      state: review.reload.state,
      issue_id: issue.id,
      actor: review.user,
      pull_request_author: pull.user,
      new_reviewer_was_added: review.new_reviewer_added?, # TODO: This should be injected to the orchestration since it's using the ActiveRecord#dirty tracking.
      event_guid:,
    }

    review.instrument(:submit, payload)

    event_flags = Events::Tier1EventPublisher.calculate_event_flags(
      event_type: :pull_request_review,
      event_action: :submitted,
      target_repository_id: repo.id,
      target_organization_id: repo.organization_id
    )

    GlobalInstrumenter.instrument("pull_request_review.submit",
      review:,
      importing: importing?,
      flags: event_flags.instrumentation_flags
    )

    Events::PullRequestReviewPublisher.submitted(review, event_flags:, event_guid:)

    submitted_comments = review.review_comments.with_submitted_state

    GitHub::PrefillAssociations.prefill_associations(submitted_comments, :pull_request, available_records: [pull])

    submitted_comments.each do |review_comment|
      review_comment.allowed = review.allowed?
      review_comment.instrument_submission
    end

    review.subscribe_and_notify unless importing?

    pull.notify_socket_subscribers
    pull.synchronize_search_index

    if review_submitted # TODO: Validate this behavior is what was expected.
      review.notify_state_changed
      review.trigger_review_decision_updated
    end
  end

  private

  sig { returns(PullRequestReviewComment) }
  memoize def comment = T.must(pull_request_review_comment)

  sig { returns(PullRequestReview) }
  memoize def review = T.must(comment.pull_request_review)

  sig { returns(PullRequestReviewThread) }
  memoize def thread = T.must(comment.pull_request_review_thread)

  sig { returns(PullRequest) }
  memoize def pull = T.must(pull_request)

  sig { returns(Repository) }
  memoize def repo = T.must(repository)
end
