# typed: true
# frozen_string_literal: true

class Api::OrganizationCodeScanningDismissalRequests < Api::App
  include Api::App::CodeScanningHelpers

  get "/organizations/:organization_id/dismissal-requests/code-scanning", operation_id: "code-scanning/list-org-dismissal-requests" do
    org = T.let(find_org!, Organization)

    control_access :view_org_code_scanning_alert_dismissal_requests,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    filter_results = check_request_filters!(params)
    page_size = filter_results[:page_size]

    if current_user.is_a?(Bot)
      installation = T.must(current_user.installation)

      if installation.installed_on_selected_repositories? && installation.repository_ids.empty?
        # Return early if the installation has no repositories.
        deliver!(:code_scanning_dismissal_request_hash, [])
      end

      dismissal_requests, has_more = org.fetch_bypass_requests(
        repository: filter_results[:repository],
        page: params[:page].to_i,
        page_size: filter_results[:page_size],
        approver: filter_results[:reviewer],
        requester: filter_results[:requester],
        time_period: filter_results[:time_period],
        request_status: filter_results[:request_status],
        request_types: [::CodeScanning::AlertDismissalService::EXEMPTION_REQUEST_TYPE],
      )

      if current_user.installation.installed_on_selected_repositories?
        # If the installation is installed on selected repositories, we need to filter the requests
        # Ideally, this should be done in the `fetch_exemption_requests_with_permissions_checking` method,
        # but for now we filter here.
        dismissal_requests = dismissal_requests.filter do |request|
          installation.repository_ids.include?(request.repository_id)
        end
      end
    else
      dismissal_requests, has_more = Exemptions::BatchExemptionRequestQuery.new(org).fetch_exemption_requests_with_permissions_checking(
        current_user,
        :read_code_scanning,
        repository: filter_results[:repository],
        organization: org,
        requester: filter_results[:requester],
        approver: filter_results[:reviewer],
        time_period: filter_results[:time_period],
        request_status: filter_results[:request_status],
        request_types: [::CodeScanning::AlertDismissalService::EXEMPTION_REQUEST_TYPE],
        limit: 100,
        page: (params[:page].to_i + 1), # The underlying method expects 1-based pagination, but the API uses 0-based.
        page_size:
      )
    end
    build_pagination_link_headers(params[:page].to_i, page_size, has_more)
    deliver(:code_scanning_dismissal_request_hash, dismissal_requests, request_source: org)
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
    # ensure repository is valid and it exists
    if params[:repository_name].present?
      repo_name = params[:repository_name].strip
      deliver_error!(422, message: "Invalid repository name") if repo_name.blank? || repo_name.length > Repository::NAME_MAX_LENGTH

      repository = @current_org.repositories.find_by(name: repo_name)
      deliver!(:code_scanning_dismissal_request_hash, []) if repository.nil?
    end

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
