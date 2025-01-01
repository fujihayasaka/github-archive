# typed: strict
# frozen_string_literal: true

class Stafftools::Businesses::CustomRoles::EnterpriseRoleAssignmentsController < Stafftools::Businesses::BusinessBaseController
  include RoleAssignments::SearchHelper

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
    selected_tab, query = parse_search_query
    role_assignment_fetcher = RoleAssignments::FetchRoleAssignments.new(target: this_business, query:, stafftools: true)
    payload = {
      slug: this_business.slug,
      currentPage: current_page,
      usersCount: role_assignment_fetcher.total_user_role_assignments,
      teamsCount: role_assignment_fetcher.total_business_team_role_assignments,
      selectedTab: selected_tab,
      hasWriteAccess: false,
      canViewEnterpriseTeams: true,
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
