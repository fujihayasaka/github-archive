# typed: true
# frozen_string_literal: true

class Businesses::People::EnterpriseInstallationsController < Businesses::BusinessController
  before_action :read_enterprise_members_required
  before_action :dotcom_required
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
    installations = business_user_account.user_enterprise_installations(
      query: query_args[:query],
      order_by_field: "host_name",
      order_by_direction: "ASC",
      role: query_args[:role],
    ).paginate(page: current_page)

    if request.xhr?
      headers["Cache-Control"] = "no-cache, no-store"
      render partial: "business_user_accounts/enterprise_installations_list", locals: {
        user_account: business_user_account,
        installations: installations,
        query: query_param,
      }
    else
      organization_count = business_user_account.enterprise_organizations(current_user).count
      team_count = business_user_account.enterprise_teams.count
      outside_collaborator_repositories_count = \
        person.outside_collaborator_repositories(business: this_business)&.count.to_i

      render "business_user_accounts/enterprise_installations", locals: {
        user_account: business_user_account,
        installations: installations,
        organization_count: organization_count,
        team_count: team_count,
        outside_collaborator_repositories_count: outside_collaborator_repositories_count,
        query: query_param,
      }
    end
  end
end
