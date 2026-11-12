# frozen_string_literal: true

# This job is responsible for finding all the open Pull Requests that belong to
# the given DependencyGroup and closing them out.
class CleanupDependencyGroupPullRequestsJob < ApplicationJob
  queue_as :default
  default_retries_for_idempotent_jobs

  CLOSE_REASON = "dependency_group_deleted"

  def perform(dependency_group_id)
    dependency_group = DependencyGroup.find(dependency_group_id)

    return if dependency_group.active?

    dependency_group.pull_requests.open.find_each do |pull_request|
      ClosePullRequestJob.perform_later(
        pull_request: pull_request,
        reason: CLOSE_REASON
      )
    end
  end
end
