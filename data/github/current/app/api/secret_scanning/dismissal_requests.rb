# typed: true
# frozen_string_literal: true

class Api::SecretScanning::DismissalRequests < Api::App
  EXEMPTION_REQUEST_STATUSES = %w[all completed approved cancelled expired denied open].freeze
  TIME_PERIODS = %w[hour day week month].freeze

  patch "/repositories/:repository_id/dismissal-requests/secret-scanning/:alert_number", operation_id: "secret-scanning/review-dismissal-request" do
    repo = find_repo!

    control_access :review_secret_scanning_alert_dismissal_requests,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    req = receive_with_openapi

    number = params[:alert_number]
    exemption_request = ::SecretScanning::Services::DelegatedAlertClosuresService.new.existing_alert_closure_request(repo, number)
    deliver_error!(404, message: "Dismissal request not found") unless exemption_request
    deliver_error!(403, message: "User is not a valid reviewer") unless exemption_request.is_valid_reviewer?(current_user)
    deliver_error!(422, message: "Dismissal request has been cancelled") if exemption_request.cancelled?
    deliver_error!(422, message: "Dismissal request has already been reviewed") if exemption_request.has_undismissed_review_by_any_reviewer?

    message = req["message"]&.strip
    is_success_msg, reason_msg = ::SecretScanning::Services::DelegatedAlertClosuresService.validate_request_message(message)
    deliver_error!(422, message: reason_msg) unless is_success_msg

    status = req["status"]&.strip&.downcase
    exemption_res, reason_review = ::SecretScanning::Services::DelegatedAlertClosuresService.new.review_exemption_request!(
      exemption_request:,
      status:,
      message:,
      user: current_user,
      repo:,
    )
    deliver_error!(422, message: reason_review) unless exemption_res

    deliver_raw({ dismissal_review_id: exemption_res.id })
  end

  get "/repositories/:repository_id/dismissal-requests/secret-scanning/:alert_number", operation_id: "secret-scanning/get-dismissal-request" do
    repo = T.let(find_repo!, Repository)
    control_access :view_secret_scanning_alert_dismissal_request,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    alert_number = params[:alert_number]
    exemption_request = ::Exemptions::ExemptionRequest.where(request_type: SecretScanning::ExemptionConstants::CLOSURE_EXEMPTION_REQUEST_TYPE, repository: repo, resource_identifier: alert_number).order(created_at: :asc).last
    deliver(:delegated_bypass_hash, exemption_request, request_source: repo)
  end

  get "/repositories/:repository_id/dismissal-requests/secret-scanning", operation_id: "secret-scanning/list-repo-dismissal-requests" do
    repo = T.let(find_repo!, Repository)

    control_access :review_secret_scanning_alert_dismissal_requests,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    filter_results = check_request_filters!(params)
    page_size = filter_results[:page_size]

    exemption_requests, has_more = repo.fetch_bypass_requests(
      repository: repo,
      page: params[:page].to_i,
      page_size:,
      approver: filter_results[:reviewer],
      requester: filter_results[:requester],
      time_period: filter_results[:time_period],
      request_status: filter_results[:request_status],
      request_types: [::SecretScanning::ExemptionConstants::CLOSURE_EXEMPTION_REQUEST_TYPE],
    )

    build_pagination_link_headers(params[:page].to_i, page_size, has_more)
    deliver(:delegated_bypass_hash, exemption_requests, request_source: repo)
  end

  get "/organizations/:organization_id/dismissal-requests/secret-scanning", operation_id: "secret-scanning/list-org-dismissal-requests" do
    org = T.let(find_org!, Organization)

    control_access :review_org_secret_scanning_alert_dismissal_requests,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    filter_results = check_request_filters!(params)

    page_size = filter_results[:page_size]
    if params[:repository_name].present?
      repo_name = params[:repository_name].strip
      deliver_error!(422, message: "Invalid repository name") if repo_name.blank? || repo_name.length > Repository::NAME_MAX_LENGTH

      repository = org.repositories.find_by(name: params[:repository_name])
      deliver!(:delegated_bypass_hash, []) if repository.nil?
    end

    exemption_requests, has_more = org.fetch_bypass_requests(
      repository:,
      page: params[:page].to_i,
      page_size:,
      approver: filter_results[:reviewer],
      requester: filter_results[:requester],
      time_period: filter_results[:time_period],
      request_status: filter_results[:request_status],
      request_types: [::SecretScanning::ExemptionConstants::CLOSURE_EXEMPTION_REQUEST_TYPE],
    )

    build_pagination_link_headers(params[:page].to_i, page_size, has_more)
    deliver(:delegated_bypass_hash, exemption_requests, request_source: org)
  end

  private

  sig { params(page: Integer, per_page: Integer, has_next_page: T::Boolean).void }
  def build_pagination_link_headers(page, per_page, has_next_page)
    @links.add_current({ page: 1, per_page: per_page }, rel: "first") if page > 1
    @links.add_current({ page: page - 1, per_page: per_page }, rel: "prev") if page > 1
    @links.add_current({ page: page + 1, per_page: per_page }, rel: "next") if has_next_page
  end

  sig { params(params: T.untyped).returns(T::Hash[Symbol, T.untyped]) }
  def check_request_filters!(params)
    # ensure approver is valid if it exists
    if params[:reviewer].present?
      reviewer = User.find_by_login(params[:reviewer])
      if reviewer.nil?
        # Return empty result if filter is invalid
        deliver!(:delegated_bypass_hash, [])
      end
    end

    # ensure requester is valid if it exists
    if params[:requester].present?
      requester = User.find_by_login(params[:requester])
      if requester.nil?
        # Return empty result if filter is invalid
        deliver!(:delegated_bypass_hash, [])
      end
    end

    # ensure time period is valid
    time_period = if params[:time_period]
      deliver_error!(422, message: "Invalid time period") unless TIME_PERIODS.include?(params[:time_period])
      params[:time_period]
    else
      "day"
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
end
