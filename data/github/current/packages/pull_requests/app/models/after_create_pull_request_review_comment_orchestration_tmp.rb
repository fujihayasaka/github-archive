# typed: true
# frozen_string_literal: true

# TODO: Delete this tmp file after the PullRequestReviewCommentOrchestration retention period is over.
# As of writing, the retention period is scheduled to end after 2026-01-15.

class AfterCreatePullRequestReviewCommentOrchestrationTmp < PullRequestReviewCommentOrchestration
  include PullRequests::Orchestrations::DataAttributes
  include GitHub::Memoizer

  data :actor, User
  data :importing, Types::Boolean, default: false, required: false
  data :review_submitted, Types::Boolean, default: false, required: false # Was the review submitted?
  data :new_reviewer_was_added, Types::Boolean, default: false, required: false
  data :position_is_used, Types::Boolean, default: false, required: false

  job_start

  step :instrument_creation_for_comment do
    return unless comment = self.comment
    comment.position_is_used = position_is_used
    comment.instrument_creation
  end

  step :instrument_creation_for_thread do
    return unless thread = self.thread
    thread.instrument(:create)

    GlobalInstrumenter.instrument("pull_request_review_thread.create", {
      pull_request_review_thread: thread,
      repository:,
    })
  end


  step :update_pull_request_counters_for_review do
    return unless pull = self.pull
    pull.update_review_and_comment_counts
  end


  private

  sig { returns(T.nilable(PullRequestReviewComment)) }
  memoize def comment = pull_request_review_comment

  sig { returns(T.nilable(PullRequestReview)) }
  memoize def review = comment&.pull_request_review

  sig { returns(T.nilable(PullRequestReviewThread)) }
  memoize def thread = comment&.pull_request_review_thread

  sig { returns(T.nilable(PullRequest)) }
  memoize def pull = pull_request

  sig { returns(T.nilable(Repository)) }
  memoize def repo = repository
end
