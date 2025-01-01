# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class RepositoryAddTeamsJob < ApplicationJob
  queue_as :repository_add_teams
  retry_on_dirty_exit

  resolve_tenant_context do |repo_id|
    Repositories::Public.resolve_tenant(id: repo_id)
  end

  # Perform the long running portion of a adding teams of a repository
  # to another one. Used when forking a repository.
  #
  # repo_id         - The repository id of the new repo the teams get added to.
  # other_repo_id   - The repository id of the source repo the teams are read from.
  #
  def perform(repo_id, other_repo_id)
    repo = Repositories.domain.by_id(repo_id)
    return if repo.blank?

    other_repo = Repositories.domain.by_id(other_repo_id)
    return if other_repo.blank?

    # rubocop:todo GitHub/AvoidCast
    with_write { T.cast(repo, Repository).add_teams_of!(other_repo) }

    success = (T.cast(other_repo, Repository).teams.pluck(:id) - T.cast(repo, Repository).teams.pluck(:id)).empty?
    # rubocop:enable GitHub/AvoidCast
    GitHub.dogstats.increment("repository_add_teams_job.team_match", tags: ["success:#{success}"])
  end
end
