# typed: true
# frozen_string_literal: true

class Api::RepositoryCodeScanningDismissalRequests < Api::App
  include Api::App::CodeScanningHelpers
  EXEMPTION_REQUEST_STATUSES = %w[all pending approved expired denied].freeze
  TIME_PERIODS = %w[hour day week month].freeze
  ALERT_DISMISSAL_DISABLED_MESSAGE = "Delegated alert dismissal must be enabled for this repository"
  NOT_A_VALID_REVIEWER_MESSAGE = "User must be a valid reviewer"

  get "/repositories/:repository_id/code-scanning/dismissal-requests", operation_id: "code-scanning/list-dismissal-requests-for-repo" do
    repo = T.let(find_repo!, Repository)

    ensure_read_access_and_code_scanning_enabled!(repo, forbid: repo.public?)

    deliver_error!(403, message: ALERT_DISMISSAL_DISABLED_MESSAGE) unless CodeScanning::AlertDismissalService.new(repo).enabled_for_api?

    control_access :read_code_scanning,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true,
      forbid_message: code_scanning_forbid_read_message

    filter_results = check_request_filters!(params)
    page_size = filter_results[:page_size]

    # reusing this method, maybe rename the method to make it more generic?
    dismissal_requests, has_more = repo.fetch_bypass_requests(
      repository: repo,
      page: params[:page].to_i,
      page_size:,
      approver: filter_results[:reviewer],
      requester: filter_results[:requester],
      time_period: filter_results[:time_period],
      request_status: filter_results[:request_status],
      request_types: [::CodeScanning::AlertDismissalService::EXEMPTION_REQUEST_TYPE],
    )

    build_pagination_link_headers(params[:page].to_i, page_size, has_more)
    deliver(:code_scanning_dismissal_request_hash, dismissal_requests, request_source: repo)
  end

  get "/repositories/:repository_id/code-scanning/dismissal-requests/:dismissal_request_number", operation_id: "code-scanning/get-dismissal-request-for-repo" do
    repo = T.let(find_repo!, Repository)

    ensure_read_access_and_code_scanning_enabled!(repo, forbid: repo.public?)

    deliver_error!(403, message: ALERT_DISMISSAL_DISABLED_MESSAGE) unless CodeScanning::AlertDismissalService.new(repo).enabled_for_api?

    control_access :read_code_scanning,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true,
      forbid_message: code_scanning_forbid_read_message

    dismissal_request = CodeScanning::AlertDismissalService.find_request_by_number(repository: repo, request_number: params[:dismissal_request_number].to_i)
    deliver(:code_scanning_dismissal_request_hash, dismissal_request, request_source: repo)
  end

  patch "/repositories/:repository_id/code-scanning/dismissal-requests/:dismissal_request_number", operation_id: "code-scanning/review-dismissal-request-for-repo" do
    repo = find_repo!

    ensure_read_access_and_code_scanning_enabled!(repo, forbid: repo.public?)

    deliver_error!(403, message: ALERT_DISMISSAL_DISABLED_MESSAGE) unless CodeScanning::AlertDismissalService.new(repo).enabled_for_api?
    deliver_error!(403, message: NOT_A_VALID_REVIEWER_MESSAGE) unless CodeScanning::AlertDismissalService.is_valid_reviewer?(repository: repo, user: current_user)

    control_access :write_code_scanning,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true,
      forbid_message: code_scanning_forbid_write_message

    req = receive_with_openapi

    number = params[:dismissal_request_number]
    dismissal_request = ::Exemptions::ExemptionRequest.where(request_type: CodeScanning::AlertDismissalService::EXEMPTION_REQUEST_TYPE, repository: repo, number:).first
    deliver_error!(404, message: "Dismissal request not found") unless dismissal_request
    deliver_error!(422, message: "Dismissal request has been cancelled") if dismissal_request.cancelled?
    deliver_error!(422, message: "Dismissal request has already been reviewed") if dismissal_request.has_undismissed_review_by_any_reviewer?
    deliver_error!(422, message: "Dismissal request has expired") if dismissal_request.expired?

    message = req["message"]&.strip
    is_success_msg, reason_msg = CodeScanning::AlertDismissalService.validate_request_message(message)
    deliver_error!(422, message: reason_msg) unless is_success_msg

    status = req["status"]&.strip&.downcase
    begin
      CodeScanning::AlertDismissalService.review_dismissal_request!(
        dismissal_request:,
        status:,
        message:,
        user: current_user,
        repo:,
      )
    rescue CodeScanning::AlertDismissalService::AlertDismissalError
      deliver_error!(422, message: "Failed to review the dismissal request")
    end

    deliver_empty status: 204
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
        deliver!(:code_scanning_dismissal_request_hash, [])
      end
    end

    # ensure requester is valid if it exists
    if params[:requester].present?
      requester = User.find_by_login(params[:requester])
      if requester.nil?
        # Return empty result if filter is invalid
        deliver!(:code_scanning_dismissal_request_hash, [])
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
end
