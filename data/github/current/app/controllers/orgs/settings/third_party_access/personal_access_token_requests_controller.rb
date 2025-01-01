# typed: true
# frozen_string_literal: true

class Orgs::Settings::ThirdPartyAccess::PersonalAccessTokenRequestsController < Orgs::Controller
  include PersonalAccessTokensControllerHelper

  before_action :organization_admin_required
  before_action :ensure_trade_restrictions_allows_org_settings_access
  before_action :require_org_enrolled, except: [:index]
  before_action :redirect_to_onboarding_if_not_enrolled, only: [:index]
  before_action :current_grant_request_required, only: [:show, :approve, :deny]
  javascript_bundle :settings

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
    only: %i(index show toolbar_actions)

  PER_PAGE = 25
  QUERY_BATCH_SIZE = 1000

  def index
    grant_requests = fetch_grant_requests(params[:q])

    paginated_grant_requests = grant_requests.paginate(
      page: current_page,
      per_page: PER_PAGE,
    )

    if request.xhr?
      render partial: "orgs/settings/third_party_access/personal_access_token_requests/requests_container",
        locals: { grant_requests: paginated_grant_requests }, formats: :html
    else
      render "orgs/settings/third_party_access/personal_access_token_requests/index", locals: { grant_requests: paginated_grant_requests }
    end
  end

  def show
    render "orgs/settings/third_party_access/personal_access_token_requests/show", locals: {
      access: current_grant_request.user_programmatic_access,
      grant_request: current_grant_request,
      grant: current_grant
    }
  end

  def approve # rubocop:todo GitHub/UseRestfulActions
    access = current_grant_request.user_programmatic_access

    grant = ProgrammaticAccessGrantRequest::Service.approve(current_grant_request, current_user, entry_point: :personal_access_token_requests_controller_approve)

    if grant.errors.any?
      redirect_to settings_org_personal_access_token_request_path(current_organization, current_grant_request.id),
        flash: { error: grant.errors.full_messages.to_sentence }
    else
      redirect_to settings_org_personal_access_token_path(current_organization, grant.id),
        flash: { notice: "The request was successfully approved" }
    end
  end

  def bulk_approve # rubocop:todo GitHub/UseRestfulActions
    grant_request_ids = params.fetch(:grant_request_ids, "").split(",")

    unless grant_request_ids.any?
      return redirect_to settings_org_personal_access_token_requests_path(current_organization),
        flash: { error: "Unable to approve requests, please try again or contact customer support if you still see this error." }
    end

    result = ProgrammaticAccessGrantRequest.bulk_approve(grant_request_ids, @current_user, @current_organization, entry_point: :personal_access_token_requests_controller_bulk_approve)

    if result.errors.any?
      redirect_to settings_org_personal_access_token_requests_path(current_organization),
        flash: { error: "Unable to approve requests, please try again or contact customer support if you still see this error." }
    else
      redirect_to settings_org_personal_access_token_requests_path(current_organization),
        flash: { notice: "Approved access for all selected requests" }
    end
  end

  def deny # rubocop:todo GitHub/UseRestfulActions
    access = current_grant_request.user_programmatic_access
    target = current_grant_request.target

    reason = fetch_deny_reason
    grant_request = ProgrammaticAccessGrantRequest.deny(current_grant_request, current_user, reason)

    if grant_request&.errors.any?
      redirect_to settings_org_personal_access_token_request_path(current_organization, current_grant_request.id),
        flash: { error: grant_request.errors.full_messages.to_sentence }
    else
      redirect_to settings_org_personal_access_token_requests_path(current_organization),
        flash: { notice: "The request was successfully denied" }
    end
  end

  def bulk_deny # rubocop:todo GitHub/UseRestfulActions
    grant_request_ids = params.fetch(:grant_request_ids, "").split(",")
    reason = fetch_deny_reason

    unless grant_request_ids.any?
      return redirect_to settings_org_personal_access_token_requests_path(current_organization),
        flash: { error: "Unable to deny requests, please try again or contact customer support if you still see this error." }
    end

    results = ProgrammaticAccessGrantRequest.bulk_deny(grant_request_ids, @current_user, @current_organization, reason)

    if results.errors.any?
      redirect_to settings_org_personal_access_token_requests_path(current_organization),
        flash: { error: "Unable to deny requests, please try again or contact customer support if you still see this error." }
    else
      redirect_to settings_org_personal_access_token_requests_path(current_organization),
        flash: { notice: "Denied access for all selected requests" }
    end
  end

  def toolbar_actions # rubocop:todo GitHub/UseRestfulActions
    # preload accesses because we show token names in the approve and deny confirmation dialogs
    grant_requests = ProgrammaticAccessGrantRequest.
               with_target(current_organization).
               where(id: params[:grant_request_ids]).
               preload(:user_programmatic_access)

    render partial: "orgs/settings/third_party_access/personal_access_token_requests/toolbar_actions",
           locals: {
             organization: current_organization,
             selected_grant_requests: grant_requests
           }
  end

  private

  def fetch_grant_requests(query)
    unless query.present?
      return ProgrammaticAccessGrantRequest.
        with_target(current_organization).
        joins(:user_programmatic_access).
        preload(user_programmatic_access: [:owner])
    end

    filters = {}
    filters[:owner] = fetch_from_filter(current_organization, "owner", query)
    filters[:repository] = fetch_from_filter(current_organization, "repository", query)
    filters[:permission] = fetch_from_filter(current_organization, "permission", query)
    return ProgrammaticAccessGrantRequest.none if filters.values.all?(&:blank?)

    ProgrammaticAccessGrantRequest.
      with_target_and_filters(current_organization, filters).
      joins(:user_programmatic_access).
      preload(user_programmatic_access: [:owner])
  end

  def fetch_owner_from_filter(query)
    return unless query.present?
    return unless (result = query.match(OWNER_REGEX))
    User.find_by_login(result[:login])
  end

  def fetch_deny_reason
    reason = params.fetch(:reason, nil)
    reason.blank? ? nil : reason
  end

  def current_grant_request_required
    render_404 unless current_grant_request
  end

  memoize def current_grant_request
    ProgrammaticAccessGrantRequest.from_target_and_id(current_organization, params[:id])
  end

  memoize def current_grant
    current_grant_request.grant
  end

  def redirect_to_onboarding_if_not_enrolled
    return if current_organization.patsv2_enabled?
    return render_404 unless current_user.patsv2_enabled?

    redirect_to settings_org_personal_access_tokens_onboarding_path(current_organization)
  end

  def require_org_enrolled
    return render_404 unless current_organization.patsv2_enabled?
  end
end
