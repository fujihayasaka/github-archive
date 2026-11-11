# frozen_string_literal: true

# Run in production every week
#
# Enqueues jobs to check which repos have flaky test suites.
module ScheduledJobs
  # TODO: Investigate moving this to run every Nth RepositoryPush
  #
  # This schedule job is effectively unbounded and will take longer
  # as the number of Repos grow. The markers we use to evaluate CI
  # health will only change with pushes to the `default_branch` which
  # we already observe.
  #
  # We could run these checks as part of that observer to spread
  # out the work and avoid checking repos that aren't changing often.
  class EnqueueRepoCiChecks < ApplicationScheduledJob
    queue_as :default

    schedule interval: 1.week

    def perform
      eligible_repo_scope.find_each do |repo|
        CheckRepoHasCiJob.perform_later(repo: repo)
      end
    end

    private

    def eligible_repo_scope
      Repo.where(paused_at: nil)
    end

    def now
      Time.now.utc
    end
  end
end
