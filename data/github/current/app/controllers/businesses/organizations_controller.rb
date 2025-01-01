# typed: true
# frozen_string_literal: true

class Businesses::OrganizationsController < Businesses::BusinessController
  before_action :login_required, only: :index
  before_action :require_organization_create_permission, only: [:new, :create]
  before_action :dotcom_required, only: [:destroy]
  before_action :require_organization_creatable, only: [:new, :create]
  before_action :sudo_filter, only: [:new, :create]
  before_action :business_not_downgraded_to_free_plan_required, except: %i(index destroy)
  before_action :business_full_plan_required
  skip_before_action :organization_upgrade_purchase_not_initiated, only: %i(index)
  before_action only: %i(index) do
    T.bind(self, Businesses::OrganizationsController)
    business_access_required(allow_members: true, allow_unaffiliated: this_business&.supports_unaffiliated_user_accounts?)
  end
  skip_before_action :cap_pagination, only: :index

  javascript_bundle :businesses

  # required to be able to make requests to this endpoint from react apps using the verifiedFetch function
  include ApplicationController::VerifiedFetchDependency
  allow_verified_fetch only: [:create]

  include ApplicationController::JsonDependency
  before_action :try_parse_json_params, only: [:create]

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    only: %i(index)

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:new]

  depends_on_clusters ApplicationRecord::Copilot, only: [:new], optional: true

  stylesheet_bundle :signup

  def index
    query_args = parse_query_string(query_param,
      filter_map: BusinessesHelper::ORGANIZATION_QUERY_FILTERS,
    )
    organizations = this_business.filtered_organizations(
        viewer: current_user,
        viewer_role: query_args[:viewer_role],
        two_factor_policy: query_args[:two_factor_policy].present? ? query_args[:two_factor_policy] : nil,
        has_deploy_keys: query_args[:has_deploy_keys].present? ? query_args[:has_deploy_keys] == "true" : nil,
        query: query_args[:query],
    ).includes(:profile).paginate(page: current_page, per_page: PAGE_SIZE)
    org_ids = organizations.pluck(:id)
    organization_transfers = organization_transfers(org_ids)

    respond_to do |format|
      format.html do
        show_create_org_ui = Business::OrganizationPermission.new(
          this_business, current_user
        ).can_create_organization?(check_licenses: false)
        if request.xhr?
          headers["Cache-Control"] = "no-cache, no-store"
          render partial: "businesses/organizations_list", locals: {
            organizations: organizations,
            organization_transfers: organization_transfers,
            show_create_org_ui: show_create_org_ui,
            viewer_organization_abilities: viewer_organization_abilities(org_ids),
            query: query_param,
          }
        else
          render "businesses/organizations/index", locals: {
            is_business_owner: is_business_owner?,
            can_create_organization: is_business_owner? || Authz.domain.check_allowed(
              current_user,
              :create_enterprise_organizations,
              this_business
            ),
            organizations: organizations,
            organization_transfers: organization_transfers,
            show_create_org_ui: show_create_org_ui,
            viewer_organization_abilities: viewer_organization_abilities(org_ids),
            query: query_param,
          }
        end
      end
    end
  end

  def new
    render "businesses/organizations/new", locals: {
      current_organization: this_business.organizations.build,
    }
  end

  # Creates a fresh organization that belongs to `this_business`
  def create
    if this_business.trial_org_creation_limit_reached?
      flash[:error] = message = "Upgrade to Enterprise to create more organizations."
      if request.xhr?
        render json: { message: }, status: :unprocessable_entity
      else
        redirect_to new_enterprise_organization_path(this_business)
      end
      return
    end

    new_org_params = create_params.merge(
      company_name: this_business.name,
      billing_email: current_user.primary_user_email,
      admin_logins: [current_user.login], # rubocop:disable GitHub/DoNotAllowLogin login used internally to lookup user, see Organization::Creator#perform
    )

    # Plan is overwritten in organization creator, passing as free here
    creator_result = Organization::Creator.perform \
      current_user,
      GitHub::Plan.free,
      new_org_params,
      business_owned: true,
      business: this_business

    if creator_result.success?
      if request.xhr?
        head :ok
      else
        if is_business_owner?
          redirect_to invite_enterprise_organization_url(this_business, creator_result.organization)
        else
          redirect_to enterprise_organizations_path(this_business)
        end
      end
    else
      flash.now[:error] = message = creator_result.error_message || creator_result.organization.errors.full_messages.join(", ")
      if request.xhr?
        render json: { message: }, status: :unprocessable_entity
      else
        render "businesses/organizations/new", locals: {
          current_organization: creator_result.organization,
        }
      end
    end
  end

  def destroy
    return render_404 unless current_user && Authz.domain.check_allowed(current_user, :remove_enterprise_organizations, this_business)

    unless org = organization_from_param
      flash[:error] = "Organization #{params[:id]} does not exist."
      return redirect_to enterprise_organizations_path(this_business)
    end

    errors = []
    if GitHub.single_business_environment?
      errors << "Organizations cannot be removed from the global enterprise in this environment."
    end

    if this_business.enterprise_managed_user_enabled?
      errors << "Organizations cannot be removed from an externally managed enterprise."
    end

    unless this_business.actor_can_remove_organizations?(current_user)
      errors << "Please contact sales to modify #{this_business.name}."
    end

    membership = this_business.organization_memberships.where organization: org
    if membership.any?
      if errors.empty?
        begin
          this_business.remove_organization(org, actor: current_user, remove_unaffiliated_users: params[:remove_unaffiliated_users] == "1")
        rescue Business::OrganizationHasNoAdminsError
          errors << "Organization #{org.display_login} doesn't have any owners. An enterprise owner must \
            assume ownership of the organization before it can be removed.".squish
        end
      end
    else
      errors << "Organization #{org.display_login} doesn't belong to #{this_business.name}."
    end

    if errors.any?
      flash[:error] = errors.first
    else
      flash[:notice] = "Removed organization #{org.name} from this enterprise."
    end
    redirect_to enterprise_organizations_path(this_business)
  end

  private

  memoize def organization_from_param
    ::Organization.find_by(login: params[:id])
  end

  def create_params
    params.require(:organization).permit(:login, :profile_name)
  end

  memoize def is_business_owner?
    this_business.owner?(current_user)
  end

  def require_organization_create_permission
    business_permission_required(:create_enterprise_organizations)
  end

  def require_organization_creatable
    if !Business::OrganizationPermission.new(this_business, current_user).can_create_organization?
      flash[:error] = message = "Not enough seats to create a new organization"
      if request.xhr?
        render json: { message: }, status: :unprocessable_entity
      else
        redirect_to enterprise_organizations_path(this_business)
      end
    end
  end

  def organization_transfers(org_ids)
    # Get any org transfers that have either not completed or have failed, for the given
    # orgs in a single query
    transfers = BusinessOrganizationTransfer
      .where(from_business: this_business, organization_id: org_ids)
      .not_complete
    transfers.reduce({}) do |hash, transfer|
      hash[transfer.organization_id] = transfer
      hash
    end
  end

  def viewer_organization_abilities(org_ids)
    if this_business.indirect_abilities_feature_enabled?
      this_business.business_org_abilities(
        org_ids: org_ids, actor_ids: [current_user.id],
        include_indirect_abilities: true
      ) do |scope|
        scope.pluck(:subject_id, :action)
      end.each_with_object({}) do |(subject_id, action), abilities|
        previous_action = abilities[subject_id]
        if previous_action.nil? || Ability.can_at_least?(previous_action, action)
          abilities[subject_id] = action
        end
      end
    else
      this_business.business_org_abilities(
        org_ids: org_ids, actor_ids: [current_user.id],
      ).each_with_object({}) do |ability, abilities|
        abilities[ability.subject_id] = ability.action
      end
    end
  end
end
