# typed: true
# frozen_string_literal: true

class Api::Dependabot::DismissalRequests < Api::App
  include Api::App::DependabotAlertsHelpers

  EXEMPTION_REQUEST_STATUSES = %w[all completed approved cancelled expired denied open].freeze
  TIME_PERIODS = %w[hour day week month].freeze
  ALERT_DISMISSAL_DISABLED_MESSAGE = "Delegated alert dismissal must be enabled for this repository"
  FORBIDDEN_MESSAGE = "You are not authorized to perform this operation."
  DEFAULT_PER_PAGE = 30
  MAX_PER_PAGE = 100

  get "/repositories/:repository_id/dismissal-requests/dependabot", operation_id: "dependabot/list-dismissal-requests-for-repo" do
    repo = T.let(find_repo!, Repository)
    ensure_repo_access_and_dependabot_alerts_enabled!(repo)

    control_access :read_vulnerability_alerts,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true,
      forbid_message: FORBIDDEN_MESSAGE

    ensure_delegated_dismissal_enabled!(repo)

    filter_results = check_request_filters!(params, repo)
    page_size = filter_results[:page_size]

    dismissal_requests, has_more = repo.fetch_bypass_requests(
      repository: repo,
      page: params[:page].to_i,
      page_size:,
      approver: filter_results[:reviewer],
      requester: filter_results[:requester],
      time_period: filter_results[:time_period],
      request_status: filter_results[:request_status],
      request_types: [::Dependabot::SecurityProduct::DelegatedClosures::CLOSURE_EXEMPTION_REQUEST_TYPE],
    )

    build_pagination_link_headers(params[:page].to_i, page_size, has_more)
    deliver(:dependabot_dismissal_request_hash, dismissal_requests, request_source: repo)
  end

  get "/repositories/:repository_id/dismissal-requests/dependabot/:alert_number", operation_id: "dependabot/get-dismissal-request-for-repo" do
    repo = T.let(find_repo!, Repository)
    ensure_repo_access_and_dependabot_alerts_enabled!(repo)

    control_access :read_vulnerability_alerts,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true,
      forbid_message: FORBIDDEN_MESSAGE

    ensure_delegated_dismissal_enabled!(repo)

    dismissal_request = find_dismissal_request_by_alert_number(repo, params[:alert_number].to_s)
    deliver_error!(404, message: "Dismissal request not found") unless dismissal_request

    deliver(:dependabot_dismissal_request_hash, dismissal_request, request_source: repo)
  end

  post "/repositories/:repository_id/dismissal-requests/dependabot/:alert_number", operation_id: "dependabot/create-dismissal-request-for-repo", read_from_replicas: true do # rubocop:disable GitHub/DuplicateRoutesAreDefinedTogether
    repo = T.let(find_repo!, Repository)
    ensure_repo_access_and_dependabot_alerts_enabled!(repo)

    control_access :read_vulnerability_alerts,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true,
      forbid_message: FORBIDDEN_MESSAGE

    ensure_delegated_dismissal_enabled!(repo)

    req = receive_with_openapi

    dismissed_reason = req["dismissed_reason"]&.strip
    dismissed_comment = req["dismissed_comment"]&.strip

    alert_number = params[:alert_number].to_s
    alert = repo.repository_vulnerability_alerts.find_by(number: alert_number)
    deliver_error!(404, message: "Alert not found") unless alert
    deliver_error!(422, message: "Alert is not open") unless alert.open?

    feature = Dependabot::SecurityProduct::DelegatedClosures.new(repo, current_user)

    begin
      dismissal_request = ActiveRecord::Base.connected_to(role: :writing) do
        feature.create_alert_closure_request(
          current_user,
          alert_number,
          dismissed_reason,
          dismissed_comment || ""
        )
      end

      deliver(:dependabot_dismissal_request_hash, dismissal_request, request_source: repo, status: 201)
    rescue ArgumentError => e
      deliver_error!(422, message: e.message)
    end
  end

  patch "/repositories/:repository_id/dismissal-requests/dependabot/:alert_number", operation_id: "dependabot/review-dismissal-request-for-repo" do # rubocop:disable GitHub/DuplicateRoutesAreDefinedTogether
    repo = T.let(find_repo!, Repository)
    ensure_repo_access_and_dependabot_alerts_enabled!(repo)

    control_access :review_dependabot_alert_dismissal_requests,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true,
      forbid_message: FORBIDDEN_MESSAGE

    ensure_delegated_dismissal_enabled!(repo)

    req = receive_with_openapi

    dismissal_request = find_dismissal_request_by_alert_number(repo, params[:alert_number].to_s)
    deliver_error!(404, message: "Dismissal request not found") unless dismissal_request
    deliver_error!(422, message: "Dismissal request has been cancelled") if dismissal_request.cancelled?
    deliver_error!(422, message: "Dismissal request has already been reviewed") if dismissal_request.has_undismissed_review_by_any_reviewer?
    deliver_error!(422, message: "Dismissal request has expired") if dismissal_request.expired?

    message = req["message"]&.strip
    is_success_msg, reason_msg = Dependabot::SecurityProduct::DelegatedClosures.validate_request_message(message)
    deliver_error!(422, message: reason_msg) unless is_success_msg

    status = req["status"]&.strip&.downcase
    feature = Dependabot::SecurityProduct::DelegatedClosures.new(repo, current_user)
    exemption_res, reason_review = feature.review_exemption_request!(
      exemption_request: dismissal_request,
      status:,
      message:,
      user: current_user,
    )
    deliver_error!(422, message: reason_review) unless exemption_res

    deliver_raw({ dismissal_review_id: exemption_res.id })
  end

  get "/organizations/:organization_id/dismissal-requests/dependabot", operation_id: "dependabot/list-dismissal-requests-for-org" do
    org = T.let(find_org!, Organization)

    control_access :read_org_dependabot_alert_dismissal_requests,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    filter_results = check_org_request_filters!(params, org)
    page_size = filter_results[:page_size]

    if current_user.is_a?(Bot)
      installation = T.must(current_user.installation)

      if installation.installed_on_selected_repositories? && installation.repository_ids.empty?
        # Return early if the installation has no repositories.
        deliver!(:dependabot_dismissal_request_hash, [], request_source: org)
      end

      dismissal_requests, has_more = org.fetch_bypass_requests(
        repository: filter_results[:repository],
        page: params[:page].to_i,
        page_size:,
        approver: filter_results[:reviewer],
        requester: filter_results[:requester],
        time_period: filter_results[:time_period],
        request_status: filter_results[:request_status],
        request_types: [::Dependabot::SecurityProduct::DelegatedClosures::CLOSURE_EXEMPTION_REQUEST_TYPE],
      )

      if current_user.installation.installed_on_selected_repositories?
        # If the installation is installed on selected repositories, we need to filter the requests
        dismissal_requests = dismissal_requests.filter do |request|
          installation.repository_ids.include?(request.repository_id)
        end
      end
    else
      dismissal_requests, has_more = Exemptions::BatchExemptionRequestQuery.new(org).fetch_exemption_requests_with_permissions_checking(
        current_user,
        :view_dependabot_alerts,
        repository: filter_results[:repository],
        organization: org,
        requester: filter_results[:requester],
        approver: filter_results[:reviewer],
        time_period: filter_results[:time_period],
        request_status: filter_results[:request_status],
        request_types: [::Dependabot::SecurityProduct::DelegatedClosures::CLOSURE_EXEMPTION_REQUEST_TYPE],
        limit: 100,
        page: (params[:page].to_i + 1), # The underlying method expects 1-based pagination, but the API uses 0-based.
        page_size:
      )
    end

    build_pagination_link_headers(params[:page].to_i, page_size, has_more)
    deliver(:dependabot_dismissal_request_hash, dismissal_requests, request_source: org)
  end

  delete "/repositories/:repository_id/dismissal-requests/dependabot/:alert_number", operation_id: "dependabot/cancel-dismissal-request-for-repo", read_from_replicas: true do
    repo = T.let(find_repo!, Repository)
    ensure_repo_access_and_dependabot_alerts_enabled!(repo)

    control_access :read_vulnerability_alerts,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true,
      forbid_message: FORBIDDEN_MESSAGE

    ensure_delegated_dismissal_enabled!(repo)

    dismissal_request = find_dismissal_request_by_alert_number(repo, params[:alert_number].to_s)
    deliver_error!(404, message: "Dismissal request not found") unless dismissal_request
    # Return 404 for cancelled/reviewed requests - from the perspective of the cancel operation,
    # these requests are not valid targets (they're not "pending" dismissal requests)
    deliver_error!(404, message: "Dismissal request not found") if dismissal_request.cancelled?
    deliver_error!(404, message: "Dismissal request not found") if dismissal_request.has_undismissed_review_by_any_reviewer?

    # Check if user is requester or has reviewer permission
    is_requester = dismissal_request.requester_id == current_user.id
    feature = Dependabot::SecurityProduct::DelegatedClosures.new(repo, current_user)
    is_reviewer = feature.user_can_review_closure_requests?(current_user)

    unless is_requester || is_reviewer
      deliver_error!(403, message: FORBIDDEN_MESSAGE)
    end

    ActiveRecord::Base.connected_to(role: :writing) do
      dismissal_request.cancelled!
    end

    status 204
  end

  private

  sig { params(repo: Repository, alert_number: String).returns(T.nilable(Exemptions::ExemptionRequest)) }
  def find_dismissal_request_by_alert_number(repo, alert_number)
    Exemptions::ExemptionRequest
      .where(repository_id: repo.id)
      .where(request_type: ::Dependabot::SecurityProduct::DelegatedClosures::CLOSURE_EXEMPTION_REQUEST_TYPE)
      .where(resource_identifier: alert_number)
      .order(created_at: :desc)
      .first
  end

  sig { params(repo: Repository).void }
  def ensure_delegated_dismissal_enabled!(repo)
    feature = Dependabot::SecurityProduct::DelegatedClosures.new(repo)
    deliver_error!(403, message: ALERT_DISMISSAL_DISABLED_MESSAGE) unless feature.enabled?
  end

  sig { params(page: Integer, per_page: Integer, has_next_page: T::Boolean).void }
  def build_pagination_link_headers(page, per_page, has_next_page)
    @links.add_current({ page: 1, per_page: per_page }, rel: "first") if page > 1
    @links.add_current({ page: page - 1, per_page: per_page }, rel: "prev") if page > 1
    @links.add_current({ page: page + 1, per_page: per_page }, rel: "next") if has_next_page
  end

  sig { params(params: T.untyped, repo: Repository).returns(T::Hash[Symbol, T.untyped]) }
  def check_request_filters!(params, repo)
    # ensure approver is valid if it exists
    if params[:reviewer].present?
      reviewer = User.find_by_login(params[:reviewer])
      if reviewer.nil?
        # Return empty result if filter is invalid
        deliver!(:dependabot_dismissal_request_hash, [], request_source: repo)
      end
    end

    # ensure requester is valid if it exists
    if params[:requester].present?
      requester = User.find_by_login(params[:requester])
      if requester.nil?
        # Return empty result if filter is invalid
        deliver!(:dependabot_dismissal_request_hash, [], request_source: repo)
      end
    end

    # ensure time period is valid
    time_period = if params[:time_period]
      deliver_error!(422, message: "Invalid time period") unless TIME_PERIODS.include?(params[:time_period])
      params[:time_period]
    else
      "month"
    end

    # ensure result filter is valid
    request_status = if params[:request_status]
      deliver_error!(422, message: "Invalid request status") unless EXEMPTION_REQUEST_STATUSES.include?(params[:request_status])
      params[:request_status]
    else
      "all"
    end

    page_size = params[:per_page] ? params[:per_page].to_i : DEFAULT_PER_PAGE
    page_size = [page_size, MAX_PER_PAGE].min

    {
      reviewer:,
      requester:,
      time_period:,
      request_status:,
      page_size:,
    }
  end

  sig { params(params: T.untyped, org: Organization).returns(T::Hash[Symbol, T.untyped]) }
  def check_org_request_filters!(params, org)
    # ensure repository is valid and it exists
    if params[:repository_name].present?
      repo_name = params[:repository_name].strip
      deliver_error!(422, message: "Invalid repository name") if repo_name.blank? || repo_name.length > Repository::NAME_MAX_LENGTH

      repository = org.repositories.find_by(name: repo_name)
      deliver!(:dependabot_dismissal_request_hash, [], request_source: org) if repository.nil?
    end

    # ensure approver is valid if it exists
    if params[:reviewer].present?
      reviewer = User.find_by_login(params[:reviewer])
      if reviewer.nil?
        # Return empty result if filter is invalid
        deliver!(:dependabot_dismissal_request_hash, [], request_source: org)
      end
    end

    # ensure requester is valid if it exists
    if params[:requester].present?
      requester = User.find_by_login(params[:requester])
      if requester.nil?
        # Return empty result if filter is invalid
        deliver!(:dependabot_dismissal_request_hash, [], request_source: org)
      end
    end

    # these parameters are validated by the OpenAPI Spec, we still need to provide defaults.
    time_period = params[:time_period].present? ? params[:time_period] : "day"
    request_status = params[:request_status].present? ? params[:request_status] : "all"

    page_size = params[:per_page] ? params[:per_page].to_i : DEFAULT_PER_PAGE
    page_size = [page_size, MAX_PER_PAGE].min

    {
      repository:,
      reviewer:,
      requester:,
      time_period:,
      request_status:,
      page_size:,
    }
  end
end
