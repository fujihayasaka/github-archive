# typed: true
# frozen_string_literal: true

# Scheduled job to destroy Teams that failed to be destroyed.
class CleanUpDeletedTeamsJob < ApplicationJob
  queue_as :clean_up_deleted_teams
  schedule interval: 1.day

  retry_on_dirty_exit
  exempt_from_tenant_context_requirement

  UPDATED_BEFORE = 6.hours

  def perform
    # Teams with deleted set to 1 with updated_at less than
    # UPDATED_BEFORE ago are considered to have failed being
    # completely destroyed.
    teams = Team.where(["deleted = 1 AND updated_at < ?", UPDATED_BEFORE.ago])
    teams_count = teams.count

    GitHub.dogstats.count \
      "clean_up_deleted_teams.teams_requiring_deletion.count",
      teams_count
    GitHub.logger.info \
      "Found teams requiring deletion",
      "gh.teams_requiring_deletion.count": teams_count

    teams.each do |team|
      with_write { team.destroy }
    end
  end
end
