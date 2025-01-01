# typed: true
# frozen_string_literal: true

class Orgs::People::ShowView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  include Orgs::People::RoleDescriptionMethods
  include Orgs::People::RoleNameMethods
  include UrlHelpers

  attr_reader :all_repo_access
  attr_reader :organization
  attr_reader :paginated_repositories
  attr_reader :person
  attr_reader :repositories_count

  def page_title
    "#{person}'s access for #{organization}"
  end

  def role
    @role ||= Organization::Role.new(organization, person)
  end

  def all_repo_role_access_team_count
    @all_repo_access_team_count ||= calculate_all_repo_role_access_team_count
  end

  def all_repo_access_single_team
    @single_team ||= get_all_repo_access_single_team
  end

  def show_all_repo_role_notice?
    if organization.business&.enterprise_teams_org_roles_supported?
      valid_roles = %w[Team User BusinessTeam]
      all_repo_access&.keys&.any? { |key| valid_roles.include?(key) } || show_admin_notice?
    else
      all_repo_access&.key?("Team") || all_repo_access&.key?("User") || show_admin_notice?
    end
  end

  def show_admin_notice?
    role.admin?
  end

  def admin_notice_path
    org_people_path(organization, { "query" => "role:owner" })
  end

  def has_all_repo_role_access_through_multiple_teams_assignment?
    if organization.business&.enterprise_teams_org_roles_supported?
      all_repo_role_access_team_count > 1
    else
      all_repo_access.key?("Team") && all_repo_access["Team"].size > 1
    end
  end

  def all_repo_role_access_through_multiple_teams_assignment_label
    if organization.business&.enterprise_teams_org_roles_supported?
      "#{all_repo_role_access_team_count} teams"
    else
      "#{all_repo_access["Team"].size} teams"
    end
  end

  def all_repo_role_access_through_multiple_teams_assignment_path
    teams_path(organization, query: "@#{person.display_login}")
  end

  def has_all_repo_role_access_through_single_team_assignment?
    if organization.business&.enterprise_teams_org_roles_supported?
      all_repo_role_access_team_count == 1
    else
      all_repo_access.key?("Team") && all_repo_access["Team"].size == 1
    end
  end

  def all_repo_role_access_through_single_team_assignment_label
    all_repo_access_single_team.name
  end

  def all_repo_role_access_through_single_team_assignment_path
    team_path(organization, all_repo_access_single_team)
  end

  def has_all_repo_role_access_through_direct_assignment?
    all_repo_access.key?("User")
  end

  def all_repo_role_access_through_direct_assignment_path
    settings_org_role_assignments_path(organization, query: person.display_login)
  end

  def show_search_form?
    !Organization::RepositoryFilter.too_many_repos?(repositories_count)
  end

  # Public: Should the 2FA status for the person be shown? Only if 2FA is
  # enabled for the authentication system being used.
  #
  # Returns a Boolean
  def show_two_factor_status?
    GitHub.auth.two_factor_authentication_enabled?
  end

  private

  def calculate_all_repo_role_access_team_count
    org_team_count = all_repo_access.key?("Team") ? all_repo_access["Team"].size : 0
    business_team_count = all_repo_access.key?("BusinessTeam") ? all_repo_access["BusinessTeam"].size : 0
    org_team_count + business_team_count
  end

  def get_all_repo_access_single_team
    if organization.business&.enterprise_teams_org_roles_supported?
      all_repo_access.key?("Team") ? T.must(Team.find_by(id: all_repo_access["Team"].first)) : T.must(BusinessTeam.find_by(id: all_repo_access["BusinessTeam"].first))
    else
      Team.find_by(id: all_repo_access["Team"].first)
    end
  end
end
