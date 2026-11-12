# frozen_string_literal: true

class PullRequestStateMachine
  include Statesman::Machine

  state :up_to_date, initial: true
  state :pending
  state :updating
  state :merged
  state :closed

  transition from: :up_to_date, to: %i(pending updating closed merged)
  transition from: :pending, to: %i(up_to_date)
  transition from: :updating, to: %i(up_to_date closed merged)
  transition from: :merged, to: %i(up_to_date closed)
  transition from: :closed, to: %i(up_to_date merged)

  # In order to transition out of the pending state, a pull request must have
  # replaced the placeholder values in github_number, head_commit_sha, and
  # dependabot_commit_sha with valid values.
  guard_transition from: :pending, to: :up_to_date do |pull_request|
    next false if pull_request.github_number == PullRequest::PENDING_PR_NUMBER
    next false if pull_request.head_commit_sha == PullRequest::PENDING_COMMIT_SHA
    next false if pull_request.dependabot_commit_sha == PullRequest::PENDING_COMMIT_SHA

    true
  end

  after_transition(to: :merged) do |pull_request|
    # setting 1 minute delay to allow replication to complete
    CaptureCompatibilityScoreJob.set(wait: 1.minute).perform_later(pull_request)
  end
end
