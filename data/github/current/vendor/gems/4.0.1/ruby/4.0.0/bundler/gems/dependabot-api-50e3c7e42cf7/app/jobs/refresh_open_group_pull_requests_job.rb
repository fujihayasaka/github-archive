# frozen_string_literal: true

# This background job is a temporary workaround that allows us to find any queue
# refresh jobs for any existing Group Pull Request when:
# - A user clicks 'check now' in the GitHub UI
# - The configuration changes triggering a new 'scheduled' job
#
# Since the scheduled job is not currently capable of refreshing existing PRs
# within that workload, we need to find any open Group Pull Requests and trigger
# their rebase process in parallel.
#
# This job should be removed once we resolved this ADR:
#   https://github.com/github/dependabot-updates/pull/4213
class RefreshOpenGroupPullRequestsJob < ApplicationJob
  queue_as :default
  default_retries_for_idempotent_jobs

  def perform(update_config:, manual: false)
    update_config.pull_requests.open.
      joins(:dependency_group).
      where(grouped_update: true, dependency_group: { deleted_at: nil }).find_each do |pr|
      CreateScheduledRefreshJob.perform_later(
        pull_request: pr,
        event_source: "job.refresh_open_group_pull_requests",
        manual: manual
      )
    end
  end
end
