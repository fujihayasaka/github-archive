# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class TeamUpdateForkedRepositoryPermissionsJob < ApplicationJob
  queue_as :team_update_forked_repository_permissions

  retry_on GitHub::Restraint::UnableToLock

  retry_on_dirty_exit

  # One job per team/repo should run at once
  JOBS_PER_KEY = 1

  # Duplicate jobs will be prevented from running for up to:
  KEY_EXPIRES_IN = 2.minutes

  # Number of repositories to load per batch
  BATCH_SIZE = 5000

  # Perform the long running portion of updating team permissions for
  # each fork of a parent repo. Sets the permissions of the fork to the
  # team's permissions on the parent repo at the time the job is executed.
  #
  # team_id     - The team id of the team that was updated
  # repo_id     - The repository id of the parent repo.
  # actor_id    - The actor_id to set in context.
  #
  def perform(team_id, repo_id, actor_id = nil)
    team  = Team.find_by(id: team_id)
    return if team.blank?
    repo  = Repository.find_by(id: repo_id)
    return if repo.blank?

    GitHub.context.push(actor_id: actor_id) if actor_id

    key = "team-update-forked-repository-permissions-#{team.id}-#{repo.id}"

    restraint = GitHub::Restraint.new

    restraint.lock!(key, JOBS_PER_KEY, KEY_EXPIRES_IN) do
      update_repository_permission_for_forks(team, repo)
    end
  end

  # Internal: apply team permissions to all forks of a repo
  def update_repository_permission_for_forks(team, repo)
    fork_ids = (team.repository_ids & repo.descendant_ids)

    new_permission = team.permission_for(repo)

    fork_ids.each_slice(BATCH_SIZE) do |ids|
      Repository.where(id: ids).each do |forked_repo|
        Ability.throttle do
          if new_permission != team.permission_for(forked_repo)
            team.update_repository_permission(forked_repo, new_permission)
          end
        end
      end
    end
  end
end
