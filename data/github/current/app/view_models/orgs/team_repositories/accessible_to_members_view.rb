# typed: true
# frozen_string_literal: true

class Orgs::TeamRepositories::AccessibleToMembersView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  attr_reader :team, :repositories, :repo_count, :roles, :organization_roles, :member_name, :action_type, :return_to

  def initialize(**args)
    super(args)

    @team = args[:team]
    @repositories = args[:repositories]
    @roles = args[:roles]
  end

  def team_name
    team.name
  end

  def more_repositories_to_view?
    repo_count > accessible_repos_limit
  end

  def org_role_count
    organization_roles.count
  end

  private

  def accessible_repos_limit
    Orgs::TeamRepositoriesController::ACCESSIBLE_REPOS_LIMIT
  end
end
