# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class UpdateTeamRepoPermissionsJob < ApplicationJob
  queue_as :update_team_repo_permissions

  JOB_SUCCESS_STATUS = [::Team::ModifyRepositoryStatus::SUCCESS, ::Team::ModifyRepositoryStatus::DUPE]

  def perform(team, action:, repo:)
    team_modify_repo_status = with_write { team.update_repository_permission(repo, action) }
    raise RuntimeError.new(team_modify_repo_status) unless JOB_SUCCESS_STATUS.include?(team_modify_repo_status)
  end
end
