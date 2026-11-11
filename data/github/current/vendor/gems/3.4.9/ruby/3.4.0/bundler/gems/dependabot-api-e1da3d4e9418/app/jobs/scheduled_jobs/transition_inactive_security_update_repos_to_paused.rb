# frozen_string_literal: true

module ScheduledJobs
  class TransitionInactiveSecurityUpdateReposToPaused < ApplicationScheduledJob
    queue_as :default
    default_retries_for_idempotent_jobs

    schedule interval: 5.minutes

    MAX_REPOS_TO_PAUSE = 10_000

    def perform
      active_security_update_repos.each do |repo|
        repo.pause!(event_source: "scheduled-inactive-security-update-check")
      end
    end

    private

    def active_security_update_repos
      Repo.where(security_updates_enabled: true, will_pause_at: ...Time.zone.now, paused_at: nil).
        limit(MAX_REPOS_TO_PAUSE).
        joins(:update_configs).
        merge(UpdateConfig.active.where(update_schedule: "never")).
        distinct # joining to the `update_configs` table will result in one Repo per config unless we use DISTINCT
    end
  end
end
