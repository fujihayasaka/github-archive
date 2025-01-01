# typed: true
# frozen_string_literal: true

class Businesses::OutsideCollaboratorsController < Businesses::BusinessController
  include EnterpriseManagedUsersHelper

  before_action :login_required
  before_action :business_owner_required
  before_action :non_idp_managed_business_permitted, only: %i(index)
  before_action :business_full_plan_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    only: %i(index)

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    ApplicationRecord::Billing,
    only: %i(show)

  def index
    query_args = parse_query_string(query_param,
      filter_map: BusinessesHelper::OUTSIDE_COLLABS_QUERY_FILTERS,
    )
    outside_collaborators = this_business
      .filtered_outside_collaborators(
        query: query_args[:query],
        visibility: Array(query_args[:visibility]).map(&:to_sym),
        organizations: query_args[:organizations],
        two_factor: query_args[:two_factor_status]&.to_sym,
        viewer: current_user
      )
      .includes(:profile)
      .paginate(page: current_page)

    respond_to do |format|
      format.html do
        if request.xhr?
          headers["Cache-Control"] = "no-cache, no-store"
          render partial: "businesses/outside_collaborators_list", locals: {
            query: query_param,
            outside_collaborators: outside_collaborators,
          }
        else
          render "businesses/outside_collaborators", locals: {
            query: query_param,
            outside_collaborators: outside_collaborators,
            pending_collaborators_count: this_business.pending_collaborator_invitations.count,
          }
        end
      end
    end
  end

  def show
    user = User.find_by!(login: login_param)
    business_user_account = this_business.business_user_account_for(user)
    repositories = user.outside_collaborator_repositories(business: this_business)
      .order("repositories.name ASC")
      .paginate(page: current_page, per_page: PAGE_SIZE)
    org_count = this_business.organizations_for_member(user).count
    installation_count = business_user_account&.enterprise_installation_user_accounts&.count.to_i
    pending_invitations_count = this_business.pending_collaborator_invitations(login: login_param).count
    render "businesses/outside_collaborator", locals: {
      user: user,
      business_user_account: business_user_account,
      repositories: repositories,
      organization_count: org_count,
      installation_count: installation_count,
      pending_invitations_count: pending_invitations_count,
    }
  end

  private

  def non_idp_managed_business_permitted
    unless this_business&.emu_repository_collaborators_enabled?
      non_idp_managed_business_required
    end
  end

  memoize def login_param
    params[:login]
  end
end
