# typed: strict
# frozen_string_literal: true

class Stafftools::Businesses::CustomRoles::EnterpriseRoleAssignmentsController < Stafftools::Businesses::BusinessBaseController
  include RoleAssignments::SearchHelper
  include RoleAssignments::AvatarOrgsHelper

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:index]

  sig { void }
  def index
    available_roles = this_business.roles_assignable_to_target
    selected_tab, query, selected_role = parse_search_query(roles: available_roles)
    role_assignment_fetcher = RoleAssignments::FetchRoleAssignments.new(target: this_business, query:, stafftools: true, role: selected_role)
    payload = {
      slug: this_business.slug,
      currentPage: current_page,
      usersCount: role_assignment_fetcher.total_user_role_assignments,
      teamsCount: role_assignment_fetcher.total_business_team_role_assignments,
      selectedTab: selected_tab,
      hasWriteAccess: false,
      canViewEnterpriseTeams: true,
      avatarOrgs: avatar_orgs,
      availableRoles: RoleAssignments::Types::Role.from_enterprise_roles(available_roles),
      selectedRole: selected_role.present? ? RoleAssignments::Types::Role.from_model(selected_role) : nil,
    }

    if selected_tab == RoleAssignments::SearchHelper::SelectedTab::Team
      payload[:assignments] = role_assignment_fetcher.paginate_business_team_role_assignments(page: current_page)
      payload[:pageCount] = (payload[:teamsCount].to_f / RoleAssignments::FetchRoleAssignments::PAGE_SIZE).ceil
    else
      payload[:assignments] = role_assignment_fetcher.paginate_user_role_assignments(page: current_page)
      payload[:pageCount] = (payload[:usersCount].to_f / RoleAssignments::FetchRoleAssignments::PAGE_SIZE).ceil
    end

    render_react_app(
      app_name: "enterprise-role-assignments",
      payload: payload,
      page_data: { selected_link: :custom_roles },
      title: "Enterprise role assignments · #{this_business.name}",
    )
  end
end
