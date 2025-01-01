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

  def show_all_repo_role_notice?
    all_repo_access&.key?("Team") || all_repo_access&.key?("User") || show_admin_notice?
  end

  def show_admin_notice?
    role.admin?
  end

  def admin_notice_path
    org_people_path(organization, { "query" => "role:owner" })
  end

  def has_all_repo_role_access_through_multiple_teams_assignment?
    all_repo_access.key?("Team") && all_repo_access["Team"].size > 1
  end

  def all_repo_role_access_through_multiple_teams_assignment_label
    "#{all_repo_access["Team"].size} teams"
  end

  def all_repo_role_access_through_multiple_teams_assignment_path
    teams_path(organization, query: "@" + person.display_login)
  end

  def has_all_repo_role_access_through_single_team_assignment?
    all_repo_access.key?("Team") && all_repo_access["Team"].size == 1
  end

  def all_repo_role_access_through_single_team_assignment_label
    team = T.must(Team.find_by(id: all_repo_access["Team"].first))
    team.name
  end

  def all_repo_role_access_through_single_team_assignment_path
    team = T.must(Team.find_by(id: all_repo_access["Team"].first))
    team_path(organization, team)
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
end
