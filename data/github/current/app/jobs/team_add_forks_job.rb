# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class TeamAddForksJob < ApplicationJob
  queue_as :team_add_forks
  retry_on_dirty_exit

  # Perform the long running portion of a adding forks of a parent repository
  # to a team.
  #
  # team - The GlobalId of the team that was added to the parent repo
  # repo - The repository GlobalId of the parent repo.
  #
  def perform(team, repo)
    return if team.permission_for(repo).blank?

    team.add_forks_of!(repo)
  end
end
