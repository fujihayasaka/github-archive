# typed: strict
# frozen_string_literal: true

class Businesses::CodespacesSettingsController < Businesses::BusinessController

  before_action :business_owner_required
  before_action :business_not_downgraded_to_free_plan_required
  before_action :business_full_plan_required

  javascript_bundle :businesses

  include ApplicationHelper
  include ReactHelper

  # required to be able to make requests to this endpoint from react apps using the verifiedFetch function
  include ApplicationController::VerifiedFetchDependency

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    only: [:index, :search_orgs]

  allow_verified_fetch only: [:update_org_enablement]

  PER_PAGE = 10
  BAD_SELECTION_ERROR_MESSAGE = "Select an option below to continue."
  sig { void }
  def index
    render_index(organizations: orgs_matching_query.to_a)
  end

  sig { void }
  def update_org_enablement # rubocop:todo GitHub/UseRestfulActions
    Codespaces::ProcessBusinessEnablementChange.call(
      business: this_business,
      actor: current_user,
      enablement: params[:enablement] || "",
      orgs_to_update: params[:orgs_to_update] || ""
    )
    message = "Your GitHub Codespaces access policy has been updated."
    respond_to do |format|
      format.html do
        flash[:notice] = message
        redirect_to settings_codespaces_enterprise_path(this_business)
      end
      format.json do
        render json: { message: message }, status: 202
      end
    end
  rescue Codespaces::ProcessBusinessEnablementChange::InvalidEnablementError
    render_index(organizations: orgs_matching_query.to_a, error: BAD_SELECTION_ERROR_MESSAGE)
  end

  sig { void }
  def search_orgs # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.json do
        render json: {
          orgs: orgs_matching_query.map do |org|
            Codespaces::OrgPresenter.new(
              business: this_business,
              organization: org,
              disable_form: false, #this gets set on initial page load, TODO: remove this from the org component args
              avatar_url: helpers.avatar_url_for(org)
            ).serialize
          end,
          pageCount: orgs_matching_query.total_pages,
          }, status: 202
      end
    end
  end

  private

  sig { returns(Codespaces::BusinessDelegator) }
  memoize def codespaces_business
    Codespaces::BusinessDelegator.new(this_business)
  end

  sig { params(organizations: T::Array[::Organization], error: T.nilable(String)).void }
  def render_index(organizations:, error: nil)
    render "businesses/codespaces_settings/index", locals: {
      organizations:,
      show_policies: this_business.feature_enabled?(:codespaces_enterprise_policies) && this_business&.in_codespaces_salus_beta?,
      enabled_count: codespaces_business.codespaces_enabled_organizations_count,
      error:,
    }
  end

  sig { returns(T.untyped) } # using T.untyped until we have a sorbet class for pagination results
  def orgs_matching_query
    page = params[:page] || 1
    search_term = params[:query]
    query = this_business.organizations
    if search_term.present?
      query = query.where("`login` like ?", "%#{search_term}%")
    end
    query.paginate(page: page, per_page: PER_PAGE)
  end

end
