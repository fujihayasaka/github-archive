# typed: true
# frozen_string_literal: true

class Stafftools::Users::OrgRoleAssignmentsController < StafftoolsController
  include Stafftools::Users::ControllerLayoutMethods
  include GitHub::Memoizer
  include RoleAssignments::SearchHelper

  before_action :ensure_org_not_user
  before_action :ensure_user_exists
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Iam,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    ApplicationRecord::NotificationsEntries,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index], optional: true

  javascript_bundle :"org-roles"
  layout :security_layout

  preload_features [
    :authz_org_role_assignments_stafftools_queries,
    :authz_org_role_assignments_stafftools_remove_counts,
  ], only: :index

  def index
    # Available roles that users can filter by in the UI
    # Include ESM because we display ESM role assignments at the org level
    #   even though ESM isn't actually assignable to the organization target.
    available_roles = current_organization.roles_assignable_to_target
    available_roles |= [EnterpriseRole.enterprise_security_manager_role]

    selected_tab, query, selected_role = parse_search_query(roles: available_roles)
    role_assignment_fetcher = RoleAssignments::FetchRoleAssignments.new(target: current_organization, query:, stafftools: true, role: selected_role)
    payload = {
      slug: current_organization.login, # we want the shortcode for stafftools queries
      currentPage: current_page,
      usersCount: role_assignment_fetcher.total_user_role_assignments,
      teamsCount: role_assignment_fetcher.total_team_role_assignments,
      selectedTab: selected_tab,
      availableRoles: RoleAssignments::Types::Role.from_org_roles(available_roles),
      selectedRole: selected_role.present? ? RoleAssignments::Types::Role.from_model(selected_role) : nil,
    }

    if selected_tab == RoleAssignments::SearchHelper::SelectedTab::Team
      payload[:assignments] = role_assignment_fetcher.paginate_team_role_assignments(page: current_page)
      payload[:pageCount] = (payload[:teamsCount].to_f / RoleAssignments::FetchRoleAssignments::PAGE_SIZE).ceil
    else
      payload[:assignments] = role_assignment_fetcher.paginate_user_role_assignments(page: current_page)
      payload[:pageCount] = (payload[:usersCount].to_f / RoleAssignments::FetchRoleAssignments::PAGE_SIZE).ceil
    end

    render_react_app(
      app_name: "enterprise-role-assignments",
      payload:,
      layout: "stafftools/organization/security",
      page_data: { selected_link: :org_role_assignments },
      title: "Organization Role Assignments · #{current_organization.safe_profile_name}",
    )
  end

  private

  def search_parameters
    params.permit(:query, :utf8, :page, :user_id, :organization_id)
  end

  def user_scope(assignee_ids:, query:)
    user_scope = User.where(id: assignee_ids)

    if query.present?
      user_scope = user_scope.merge(User.where("users.login LIKE ?", "%#{query}%"))
    end
    user_scope
  end

  def team_scope(assignee_ids:, query:)
    team_scope = Team.where(id: assignee_ids)

    if query.present?
      team_scope = team_scope.merge(Team.where("teams.slug LIKE ?", "%#{query}%"))
    end
    team_scope
  end

  def assignee_scope(assignee_ids:, query:, type:)
    assignees = if type == OrgRoles::AssignmentListComponent::AssignmentTab::User
      scope = user_scope(assignee_ids:, query:)
      scope.order("login ASC")
    else
      scope = team_scope(assignee_ids:, query:)
      scope.order("slug ASC")
    end
    assignees
  end

  def current_organization; this_user; end
end
