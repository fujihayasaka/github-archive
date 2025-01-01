# typed: true
# frozen_string_literal: true

class RemoveTeamFromRepoJob < ApplicationJob
  queue_as :remove_team_from_repo

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  def perform(team:, repo:)
    with_write { team.remove_repository(repo) }
  end
end
