# typed: true
# frozen_string_literal: true

class BusinessUserAccountsController < ApplicationController
  include BusinessesHelper

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    ApplicationRecord::Billing,
    only: [:enterprise_installations]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    ApplicationRecord::Billing,
    only: [:organizations]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:sso]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:sso],
    optional: true

  PAGE_SIZE = 30

  before_action :business_owner_required
  before_action :dotcom_required
  before_action :saml_enabled_required, only: :sso

  def organizations # rubocop:todo GitHub/UseRestfulActions
    if business_user_account.user.present?
      return redirect_to enterprise_person_organizations_enterprise_path(
        this_business,
        business_user_account.user,
        query: query_param
      )
    end

    # since business_user_account.user is nil, we can assume this is a server-only member, so they
    # don't belong to any GHEC Organizations, so just return Organization.none (though still need
    # to paginate, so we can render correctly).
    organizations = Organization.none.paginate(page: current_page)

    if request.xhr?
      headers["Cache-Control"] = "no-cache, no-store"
      render partial: "business_user_accounts/organizations_list", locals: {
        user_account: business_user_account,
        organizations: organizations,
        query: query_param,
      }
    else
      installation_count = business_user_account.user_enterprise_installations.count
      team_count = business_user_account.enterprise_teams.count

      render "business_user_accounts/organizations", locals: {
        user_account: business_user_account,
        organizations: organizations,
        team_count: team_count,
        outside_collaborator_repositories_count: 0,
        installation_count: installation_count,
        pending_invitations_count: 0,
        query: query_param,
      }
    end
  end

  def enterprise_installations # rubocop:todo GitHub/UseRestfulActions
    if business_user_account.user.present?
      return redirect_to enterprise_person_enterprise_installations_enterprise_path(
        this_business,
        business_user_account.user,
        query: query_param
      )
    end

    query_args = parse_query_string \
      query_param, filter_map: BusinessesHelper::USER_ACCOUNT_MEMBERSHIP_QUERY_FILTERS
    installations = business_user_account.user_enterprise_installations(
      query: query_args[:query],
      order_by_field: "host_name",
      order_by_direction: "ASC",
      role: query_args[:role],
    ).paginate(page: current_page, per_page: PAGE_SIZE)

    if request.xhr?
      headers["Cache-Control"] = "no-cache, no-store"
      render partial: "business_user_accounts/enterprise_installations_list", locals: {
        user_account: business_user_account,
        installations: installations,
        query: query_param,
      }
    else
      team_count = business_user_account.enterprise_teams.count

      render "business_user_accounts/enterprise_installations", locals: {
        user_account: business_user_account,
        installations: installations,
        organization_count: 0,
        team_count: team_count,
        outside_collaborator_repositories_count: 0,
        query: query_param,
      }
    end
  end

  def sso # rubocop:todo GitHub/UseRestfulActions
    redirect_to enterprise_person_sso_enterprise_path(this_business, business_user_account.user)
  end

  private

  # Safe because :business_owner_required enusres this_business is not nil (or else 404)
  def target_for_conditional_access
    return :no_target_for_conditional_access unless this_business # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    this_business
  end

  def this_business
    business_user_account.business
  end

  def business_owner_required
    render_404 unless business_user_account.business.owner?(current_user)
  end

  memoize def business_user_account
    BusinessUserAccount.find(params[:id])
  end

  def query_param
    params[:query]
  end

  def saml_enabled_required
    render_404 unless this_business.saml_sso_enabled?
  end
end
