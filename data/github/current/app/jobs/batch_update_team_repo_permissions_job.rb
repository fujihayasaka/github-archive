# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# Updates org teams permissions/roles and deletes custom role if present and
# has not dependencies
#
# teams_repos       - Active records of team/permission or team/role association
# action_id         - Organisation admin
# action            - The permission to update to. Can be :read, :write, :admin, :triage, :maintain, or a custom role
# role              - Custom role. default: nil
# context           - Optional Hash of Strings with the teams' previous Role {:old_permission, :old_base_role}
#
# Returns nothing
class BatchUpdateTeamRepoPermissionsJob < ApplicationJob
  queue_as :update_team_repo_permissions

  JOB_SUCCESS_STATUS = [::Team::ModifyRepositoryStatus::SUCCESS, ::Team::ModifyRepositoryStatus::DUPE]

  def perform(teams_repos, actor_id, action:, role: nil, context: {})
    GitHub.context.push(actor_id: actor_id) if actor_id
    teams = fetch_teams(teams_repos)
    repos = fetch_repos(teams_repos)

    teams_repos.each do |team_repo|
      repo_id = team_repo.try(:subject_id) || team_repo.try(:target_id)
      repo = repos[repo_id]
      team = teams[team_repo.actor_id]

      team.check_valid_action(action, repo)
      team_modify_repo_status = with_write { team.update_repository_permission(repo, action, context: context) }
      raise RuntimeError.new(team_modify_repo_status) unless JOB_SUCCESS_STATUS.include?(team_modify_repo_status)
    end

    # only delete role if all dependencies are updated
    if !role.nil? && role&.all_dependencies_updated?
      if with_write { role.destroy! }
        GitHub.dogstats.increment("orgs_roles.delete.queued_to_delete", tags: ["status:deleted"])
      end
    end
  end

  private

  def fetch_teams(teams_repos)
    return @teams if defined?(@teams)
    @teams = Team.where(id: teams_repos.map(&:actor_id)).index_by(&:id)
  end

  def fetch_repos(teams_repos)
    return @repos if defined?(@repos)
    repo_ids = []
    begin
      repo_ids = teams_repos.map(&:subject_id)
    rescue NoMethodError
      repo_ids = teams_repos.map(&:target_id)
    end
    @repos = Repository.where(id: repo_ids).index_by(&:id)
  end
end
