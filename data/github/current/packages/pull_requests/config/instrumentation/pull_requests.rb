# typed: strict
# frozen_string_literal: true

# Handle cancelation of check suite when a merge group is destroyed
# this saves on cost of running actions workflows when the merge group is no longer going to be used
GitHub.subscribe("merge_group.destroyed") do |_name, _start, _ending, _transaction_id, payload|
  # Skip items which are yet to have a checkrun started for them
  # Note: Early return not supporetd in this context get JumpLocal error
  if payload[:checks_requested_at].present?
    cancel_suites_created_before = Time.current
    # Why `Time.current`? This ensures that, if the job is delayed, we don't cancel checks suites that are
    # created for this SHA after the destroy event. Say MQ is using rebase and same item is removed then re-added.
    # Why not use `checks_requested_at`? This is the time when the check suite was requested
    # not when the suite was created. So we'd not cancel some check suites.
    # See: https://github.com/github/github/pull/369991
    MergeQueueCancelCheckSuiteJob.perform_later(
      payload[:pull_request_id], payload[:head_sha], payload[:actor_id], cancel_suites_created_before
    )
  end
end
