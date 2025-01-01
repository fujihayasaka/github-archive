# typed: true
# frozen_string_literal: true

class BusinessUserAccounts::OrganizationsController < ApplicationController
  PAGE_SIZE = 30

  before_action :read_enterprise_admins_and_members_required
  before_action :dotcom_required

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    ApplicationRecord::Billing,
    only: [:index]

  def index
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

  private

  # Safe because :business_owner_required ensures this_business is not nil (or else 404)
  def target_for_conditional_access
    return :no_target_for_conditional_access unless this_business # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    this_business
  end

  def this_business
    business_user_account.business
  end

  def read_enterprise_admins_and_members_required
    render_404 unless business_user_account&.business&.actor_can_read_members?(current_user)
  end

  memoize def business_user_account
    BusinessUserAccount.find(params[:id])
  end

  def query_param
    params[:query]
  end
end
