# typed: true
# frozen_string_literal: true

class Businesses::People::OrganizationsController < Businesses::BusinessController
  before_action :business_owner_required
  before_action :business_user_account_required
  before_action :business_not_downgraded_to_free_plan_required

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    only: [:index]

  def index
    query_args = parse_query_string \
      query_param, filter_map: BusinessesHelper::USER_ACCOUNT_MEMBERSHIP_QUERY_FILTERS

    organizations = if GitHub.enterprise?
      person.filter_organizations(current_user,
        query: query_args[:query],
        order_by_field: "login",
        order_by_direction: "ASC",
        org_member_type: ::BusinessUserAccount.org_member_type_from_role(query_args[:role]),
      ).paginate(page: current_page)
    else
      business_user_account.enterprise_organizations(
        current_user,
        query: query_args[:query],
        order_by_field: "login",
        order_by_direction: "ASC",
        org_member_type: ::BusinessUserAccount.org_member_type_from_role(query_args[:role]),
      ).paginate(page: current_page)
    end

    if request.xhr?
      headers["Cache-Control"] = "no-cache, no-store"
      render partial: "business_user_accounts/organizations_list", locals: {
        user_account: business_user_account,
        user: person,
        organizations: organizations,
        query: query_param,
      }
    else
      installation_count = GitHub.enterprise? ? 0 : business_user_account.user_enterprise_installations.count
      pending_invitations_count = this_business.pending_member_invitations(login: person.login).count # rubocop:disable GitHub/DoNotAllowLogin login is needed for SQL query, see PeopleDependency#apply_login_filter
      outside_collaborator_repositories_count = person.outside_collaborator_repositories(business: this_business)&.count.to_i
      team_count = GitHub.enterprise? ? person.filter_teams(current_user).count : business_user_account.enterprise_teams.count

      render "business_user_accounts/organizations", locals: {
        user_account: business_user_account,
        user: person,
        organizations: organizations,
        team_count: team_count,
        outside_collaborator_repositories_count: outside_collaborator_repositories_count,
        installation_count: installation_count,
        pending_invitations_count: pending_invitations_count,
        query: query_param,
      }
    end
  end
end
