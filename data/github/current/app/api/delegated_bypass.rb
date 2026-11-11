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

    deliver_error! 404 unless repo.plan_supports?(:enterprise_rulesets)

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
    deliver(:delegated_bypass_hash, exemption_requests)
  end

  get "/repositories/:repository_id/bypass-requests/push-rules/:bypass_request_number", operation_id: "repos/get-repo-push-bypass-request" do
    repo = find_repo!
    control_access :write_repository_bypass_requests,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    deliver_error! 404 unless repo.plan_supports?(:enterprise_rulesets)

    exemption_request = repo.fetch_bypass_request_by_number(params[:bypass_request_number].to_i)
    deliver(:delegated_bypass_hash, exemption_request)
  end

  get "/organizations/:organization_id/bypass-requests/push-rules", operation_id: "orgs/list-push-bypass-requests" do
    org = find_org!

    control_access :write_org_bypass_requests,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    deliver_error! 404 unless org.plan_supports?(:enterprise_rulesets)

    filter_results = check_request_filters!(params)

    approver = filter_results[:reviewer]
    requester = filter_results[:requester]
    time_period = filter_results[:time_period]
    request_status = filter_results[:request_status]
    page_size = filter_results[:page_size]
    request_types = ["push_ruleset_bypass"]

    if params[:repository_name].present?
      repository = org.repositories.find_by(name: params[:repository_name])
      ensure_exemption_request_filter_exists!(repository)
    end

    exemption_requests, has_more = org.fetch_bypass_requests(repository:, page_size:, page: params[:page].to_i,
      approver: approver, requester: requester, time_period: time_period, request_status:, request_types:)

    build_pagination_link_headers(params[:page].to_i, page_size, has_more)
    deliver(:delegated_bypass_hash, exemption_requests)
  end

  get "/enterprises/:enterprise_id/bypass-requests/push-rules", operation_id: "enterprise-admin/list-push-bypass-requests" do
    enterprise = find_enterprise!

    control_access :administer_business,
      resource: enterprise,
      allow_integrations: false,
      allow_user_via_granular_actor: false

    deliver_error! 404 unless enterprise.plan_supports?(:enterprise_rulesets)

    filter_results = check_request_filters!(params)

    approver = filter_results[:reviewer]
    requester = filter_results[:requester]
    time_period = filter_results[:time_period]
    request_status = filter_results[:request_status]
    page_size = filter_results[:page_size]
    request_types = ["push_ruleset_bypass"]

    if params[:organization_name].present?
      organization = enterprise.organizations.find_by(login: params[:organization_name])
      ensure_exemption_request_filter_exists!(organization)
    end

    exemption_requests, has_more = enterprise.fetch_bypass_requests(organization:, page_size:, page: params[:page].to_i,
      approver: approver, requester: requester, time_period: time_period, request_status:, request_types:)


    build_pagination_link_headers(params[:page].to_i, page_size, has_more)
    deliver(:delegated_bypass_hash, exemption_requests)
  end

  get "/repositories/:repository_id/bypass-requests/repository-policies", operation_id: "repos/list-repo-policy-bypass-requests" do
    repo = find_repo!

    control_access :write_repository_bypass_requests,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    check_repository_delegated_bypass_supported!(repo)

    filter_results = check_request_filters!(params)

    approver = filter_results[:reviewer]
    requester = filter_results[:requester]
    time_period = filter_results[:time_period]
    request_status = filter_results[:request_status]
    page_size = filter_results[:page_size]
    request_types = ["repository_policy_ruleset_bypass"]

    exemption_requests, has_more = repo.fetch_bypass_requests(repository: repo, page_size:, page: params[:page].to_i,
      approver: approver, requester: requester, time_period: time_period, request_status:, request_types:)

    build_pagination_link_headers(params[:page].to_i, page_size, has_more)
    deliver(:delegated_bypass_hash, exemption_requests)
  end

  get "/repositories/:repository_id/bypass-requests/repository-policies/:bypass_request_number", operation_id: "repos/get-repo-policy-bypass-request" do
    repo = find_repo!
    control_access :write_repository_bypass_requests,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    check_repository_delegated_bypass_supported!(repo)

    exemption_request = repo.fetch_bypass_request_by_number(params[:bypass_request_number].to_i)
    deliver(:delegated_bypass_hash, exemption_request)
  end

  get "/organizations/:organization_id/bypass-requests/repository-policies", operation_id: "orgs/list-repo-policy-bypass-requests" do
    org = find_org!

    control_access :write_org_bypass_requests,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    check_repository_delegated_bypass_supported!(org)

    filter_results = check_request_filters!(params)

    approver = filter_results[:reviewer]
    requester = filter_results[:requester]
    time_period = filter_results[:time_period]
    request_status = filter_results[:request_status]
    page_size = filter_results[:page_size]
    request_types = ["repository_policy_ruleset_bypass"]

    if params[:repository_name].present?
      repository = org.repositories.find_by(name: params[:repository_name])
      ensure_exemption_request_filter_exists!(repository)
    end

    exemption_requests, has_more = org.fetch_bypass_requests(repository:, page_size:, page: params[:page].to_i,
      approver: approver, requester: requester, time_period: time_period, request_status:, request_types:)

    build_pagination_link_headers(params[:page].to_i, page_size, has_more)
    deliver(:delegated_bypass_hash, exemption_requests)
  end

  get "/enterprises/:enterprise_id/bypass-requests/repository-policies", operation_id: "enterprise-admin/list-repo-policy-bypass-requests" do
    enterprise = find_enterprise!

    control_access :administer_business,
      resource: enterprise,
      allow_integrations: false,
      allow_user_via_granular_actor: false

    check_repository_delegated_bypass_supported!(enterprise)

    filter_results = check_request_filters!(params)

    approver = filter_results[:reviewer]
    requester = filter_results[:requester]
    time_period = filter_results[:time_period]
    request_status = filter_results[:request_status]
    page_size = filter_results[:page_size]
    request_types = ["repository_policy_ruleset_bypass"]

    if params[:organization_name].present?
      organization = enterprise.organizations.find_by(login: params[:organization_name])
      ensure_exemption_request_filter_exists!(organization)
    end

    exemption_requests, has_more = enterprise.fetch_bypass_requests(organization:, page_size:, page: params[:page].to_i,
      approver: approver, requester: requester, time_period: time_period, request_status:, request_types:)

    build_pagination_link_headers(params[:page].to_i, page_size, has_more)
    deliver(:delegated_bypass_hash, exemption_requests)
  end

  private

  sig { params(param: String).returns(String) }
  def string_input_sanitizer(param)
    param.strip.downcase
  end

  def check_request_filters!(params)
    # ensure reviewer is valid if it exists
    if params[:reviewer].present?
      sanitized_name = string_input_sanitizer(params[:reviewer])
      reviewer = User.find_by_login(sanitized_name)
      ensure_exemption_request_filter_exists!(reviewer)
    end

    # ensure requester is valid if it exists
    if params[:requester].present?
      sanitized_name = string_input_sanitizer(params[:requester])
      requester = User.find_by_login(sanitized_name)
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

  def check_repository_delegated_bypass_supported!(source)
    deliver_error! 404 unless source.member_privilege_rulesets_enabled? &&
    source.repo_policy_bypass_enabled? &&
    source.plan_supports?(:enterprise_rulesets)
  end
end
