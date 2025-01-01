# typed: true
# frozen_string_literal: true
class Orgs::Settings::ThirdPartyAccess::PersonalAccessTokensController < Orgs::Controller
  include PersonalAccessTokensControllerHelper

  before_action :organization_admin_required
  before_action :ensure_trade_restrictions_allows_org_settings_access
  before_action :require_org_enrolled, except: [:index, :active]
  before_action :redirect_to_onboarding_if_not_enrolled, only: [:index, :active]
  before_action :current_grant_required, only: [:show, :destroy]
  javascript_bundle :settings

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Permissions,
    ApplicationRecord::Copilot,
    only: %i(index active show toolbar_actions)

  PER_PAGE = 25
  CLASSIC_VERSION = "classic".freeze

  helper_method :pats_restricted_by_policy?, :pats_enforced_by_policy?, :pats_allowed?, :pats_not_allowed?

  def index
    if params[:tab] == CLASSIC_VERSION && pats_policies_redesign_enabled?
      return render "orgs/settings/third_party_access/personal_access_tokens/classic", locals: { redesign_enabled: true }
    end
    render "orgs/settings/third_party_access/personal_access_tokens/index", locals: { redesign_enabled: pats_policies_redesign_enabled? }
  end

  def active # rubocop:todo GitHub/UseRestfulActions
    grants = fetch_grants(params[:q])

    paginated_grants = grants.paginate(
      page: current_page,
      per_page: PER_PAGE,
    )

    if request.xhr?
      render partial: "orgs/settings/third_party_access/personal_access_tokens/active_container",
        locals: { grants: paginated_grants }, formats: :html
    else
      render "orgs/settings/third_party_access/personal_access_tokens/active", locals: { grants: paginated_grants }
    end
  end

  def show
    render "orgs/settings/third_party_access/personal_access_tokens/show", locals: { grant: current_grant }
  end

  def toolbar_actions # rubocop:todo GitHub/UseRestfulActions
    # preload accesses because we show token names in the revoke confirmation dialog
    grants = ProgrammaticAccessGrant.
               with_target(current_organization).
               where(id: params[:grant_ids]).
               preload(:user_programmatic_access)

    render partial: "orgs/settings/third_party_access/personal_access_tokens/toolbar_actions",
           locals: {
             organization: current_organization,
             selected_grants: grants
           }
  end

  def destroy
    access = current_grant.user_programmatic_access

    result = ProgrammaticAccessGrant.revoke(current_grant, current_user)

    if result.errors.empty?
      flash[:notice] = "Token for #{access.owner.display_login} successfully revoked."
    else
      flash[:error] = "Unable to revoke this token, please try again or contact customer support if you still see this error."
    end

    redirect_to settings_org_active_personal_access_tokens_path(current_organization)
  end

  def bulk_destroy # rubocop:todo GitHub/UseRestfulActions
    grant_ids = params.fetch(:grant_ids, "").split(",")

    result = ProgrammaticAccessGrant.bulk_revoke(grant_ids, current_user, current_organization)

    if result.errors.empty?
      flash[:notice] = "Revoked access for all selected tokens."
    else
      flash[:error] = "Unable to revoke tokens, please try again or contact customer support if you still see this error."
    end

    # Redirect to back so that we keep any filtering/pagination context
    redirect_to :back
  end

  private

  def current_grant # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @current_grant if defined?(@current_grant)

    @current_grant = ProgrammaticAccessGrant.from_target_and_id(current_organization, params[:id])
  end

  def current_grant_required
    render_404 unless current_grant
  end

  def fetch_grants(query)
    unless query.present?
      return ProgrammaticAccessGrant.
        with_target(current_organization).
        joins(:user_programmatic_access).
        preload(:user_programmatic_access)
    end

    filters = {}
    filters[:owner] = fetch_from_filter(current_organization, "owner", query)
    filters[:repository] = fetch_from_filter(current_organization, "repository", query)
    filters[:permission] = fetch_from_filter(current_organization, "permission", query)
    return ProgrammaticAccessGrant.none if filters.values.all?(&:blank?)

    ProgrammaticAccessGrant.
      with_target_and_filters(current_organization, filters).
      joins(:user_programmatic_access).
      preload(:user_programmatic_access)
  end

  memoize def pats_restricted_by_policy?
    current_organization.personal_access_tokens_restricted_policy?
  end

  memoize def pats_enforced_by_policy?
    current_organization.personal_access_tokens_enforced_policy?
  end

  memoize def pats_allowed?
    pats_enforced_by_policy? || current_organization.personal_access_tokens_allowed?
  end

  def pats_not_allowed?
    pats_restricted_by_policy? || !pats_allowed?
  end

  def redirect_to_onboarding_if_not_enrolled
    return if current_organization.patsv2_enabled?
    return render_404 unless current_user.patsv2_enabled?

    redirect_to settings_org_personal_access_tokens_onboarding_path(current_organization)
  end

  def require_org_enrolled
    render_404 unless current_organization.patsv2_enabled?
  end

  memoize def pats_policies_redesign_enabled?
    return false unless current_organization.patsv2_enabled? && current_user.patsv2_enabled?

    current_organization.business&.feature_enabled?(:org_pat_policies_page_redesign) ||
    current_organization.feature_enabled?(:org_pat_policies_page_redesign)
  end
end
