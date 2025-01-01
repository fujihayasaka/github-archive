# typed: true
# frozen_string_literal: true

class Api::DelegatedBypass < Api::App
  include ReceiveSchemaWithOpenApi
  include Api::App::RepositoryRulesDependency
  TIME_PERIODS = %w[hour day week month].freeze
  EXEMPTION_REQUEST_STATUSES = %w[all completed cancelled expired denied open].freeze

  get "/repositories/:repository_id/bypass-requests/push-rules", operation_id: "repos/list-repo-push-bypass-requests" do
    repo = find_repo!

    control_access :write_repository_bypass_requests,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    check_delegated_bypass_supported!(repo)

    filter_results = check_request_filters!(params)

    approver = filter_results[:reviewer]
    requester = filter_results[:requester]
    time_period = filter_results[:time_period]
    request_status = filter_results[:request_status]
    page_size = filter_results[:page_size]
    request_types = ["push_ruleset_bypass"]

    exemption_requests, has_more = repo.fetch_bypass_requests(repository: repo, page_size:, page: params[:page].to_i,
      approver: approver, requester: requester, time_period: time_period, request_status:, request_types:)

    build_pagination_link_headers(params[:page].to_i, page_size, has_more)
    deliver(:delegated_bypass_hash, exemption_requests, request_source: repo)
  end

  get "/repositories/:repository_id/bypass-requests/push-rules/:bypass_request_number", operation_id: "repos/get-repo-push-bypass-request" do
    repo = find_repo!
    control_access :write_repository_bypass_requests,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    check_delegated_bypass_supported!(repo)

    exemption_request = repo.fetch_bypass_request_by_number(params[:bypass_request_number].to_i)
    deliver(:delegated_bypass_hash, exemption_request, request_source: repo)
  end

  get "/organizations/:organization_id/bypass-requests/push-rules", operation_id: "orgs/list-push-bypass-requests" do
    org = find_org!

    control_access :write_org_bypass_requests,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    check_delegated_bypass_supported!(org)

    filter_results = check_request_filters!(params)

    approver = filter_results[:reviewer]
    requester = filter_results[:requester]
    time_period = filter_results[:time_period]
    request_status = filter_results[:request_status]
    page_size = filter_results[:page_size]
    request_types = ["push_ruleset_bypass"]

    if params[:repository_name].present?
      repository = org.repositories.find_by(name: params[:repository_name])
    end

    exemption_requests, has_more = org.fetch_bypass_requests(repository:, page_size:, page: params[:page].to_i,
      approver: approver, requester: requester, time_period: time_period, request_status:, request_types:)

    build_pagination_link_headers(params[:page].to_i, page_size, has_more)
    deliver(:delegated_bypass_hash, exemption_requests, request_source: org)
  end

  private

  def check_request_filters!(params)
    # ensure approver is valid if it exists
    if params[:reviewer].present?
      reviewer = User.find_by_login(params[:reviewer])
      ensure_exemption_request_filter_exists!(reviewer)
    end

    # ensure requester is valid if it exists
    if params[:requester].present?
      requester = User.find_by_login(params[:requester])
      ensure_exemption_request_filter_exists!(requester)
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

  def ensure_exemption_request_filter_exists!(filter_option)
    if filter_option.nil?
      # Return empty result if user filter is invalid
      deliver!(:delegated_bypass_hash, [])
    end
  end

  def check_delegated_bypass_supported!(source)
    deliver_error! 404 unless source.push_rulesets_enabled? &&
     source.push_ruleset_delegated_bypass? &&
     source.plan_supports?(:enterprise_rulesets)
  end
end
