# typed: true
# frozen_string_literal: true

module ActionsMetrics::ApiUtils
  include Kernel
  include ActionsMetrics::Utils
  include ActionsUsageMetrics::Api::V1

  def get_repositories(params, org, user, session)
    search_org_repos(
      org,
      user,
      get_search_query(params),
      user_session: session
    )
  end

  def get_workflows(params, biz, org, repo, user)
    options = RequestOptions.new(
      scope: get_scope(biz, org, repo),
      limit: suggestion_limit,
      search: get_search_query(params),
      projection_options: get_projection_options(user, get_version(params, user))
    )

    search_org_workflows(biz, org, user, options)
  end

  def get_jobs(params, biz, org, repo, user)
    options = RequestOptions.new(
      scope: get_scope(biz, org, repo),
      limit: suggestion_limit,
      search: get_search_query(params),
      projection_options: get_projection_options(user, get_version(params, user))
    )

    search_org_jobs(biz, org, user, options)
  end

  def get_runner_labels(params, biz, org, repo, user)
    options = RequestOptions.new(
      scope: get_scope(biz, org, repo),
      limit: suggestion_limit,
      search: get_search_query(params),
      projection_options: get_projection_options(user, get_version(params, user))
    )

    search_runner_labels(biz, org, user, options)
  end

  def get_export_status(params, biz, org, repo, user)
    export_id = params[:export_id]
    client = get_client(biz, org, user)
    response = client.get_export_status(request: GetExportStatusRequest.new(export_id: export_id, scope: get_scope(biz, org, repo)))
    response.data.to_h
  end

  def start_export(params, biz, org, repo, user)
    version = get_version(params, user)
    set_param_defaults(params)
    tab = params[:tab]

    client = get_client(biz, org, user)

    options = RequestOptions.new(
      scope: get_scope(biz, org, repo),
      offset: 0,
      limit: (2 << 31) - 1, # max int32 - needs this because it defaults to 1000
      date_range: params[:date_range_type],
      request_type: params[:request_type],
      filters: get_filters(params, biz, org),
      order_by: get_order_by(params),
      projection_options: get_projection_options(user, version),
      custom_date_range: get_custom_date_range(params),
    )

    export_type = ExportType::EXPORT_TYPE_WORKFLOW_USAGE

    if options.request_type == :REQUEST_TYPE_PERFORMANCE
      export_type = ExportType::EXPORT_TYPE_WORKFLOW_PERFORMANCE
    end

    if tab == "jobs"
      export_type = ExportType::EXPORT_TYPE_JOB_USAGE
    elsif tab == "orgs"
      export_type = ExportType::EXPORT_TYPE_ORG_USAGE
    elsif tab == "repositories"
      export_type = ExportType::EXPORT_TYPE_REPO_USAGE
    elsif tab == "runtime"
      export_type = ExportType::EXPORT_TYPE_RUNNER_RUNTIME_USAGE
    elsif tab == "runner"
      export_type = ExportType::EXPORT_TYPE_RUNNER_TYPE_USAGE
    end

    columns = params[:headers]
    if columns.nil? || columns.length < 1
      raise "No columns specified for export"
    end

    headers = columns.map do |c|
      if c[:key] == "repository"
        ExportHeader.new(key: "repository_id", display: c[:display])
      elsif c[:key] == "org"
        ExportHeader.new(key: "owner_id", display: c[:display])
      else
        ExportHeader.new(key: c[:key], display: c[:display])
      end
    end

    request = StartExportRequest.new(
      request_options: options,
      export_type: export_type,
      headers: headers,
    )

    response = client.start_export(request: request)

    response.data.to_h
  end

  def get_metrics_data(params, biz, org, repo, user)
    version = get_version(params, user)
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    set_param_defaults(params)
    tab = params[:tab]

    client = get_client(biz, org, user)

    options = RequestOptions.new(
      scope: get_scope(biz, org, repo),
      offset: params[:offset],
      limit: params[:page_size],
      date_range: params[:date_range_type],
      request_type: params[:request_type],
      filters: get_filters(params, biz, org),
      order_by: get_order_by(params),
      projection_options: get_projection_options(user, version),
      custom_date_range: get_custom_date_range(params),
    )

    if tab == "jobs"
      request = GetJobUsageRequest.new(
        request_options: options
      )

      response = client.get_job_usage(request: request)
    elsif tab == "orgs"
      request = GetOrgUsageRequest.new(
        request_options: options
      )

      response = client.get_org_usage(request: request)
    elsif tab == "repositories"
      request = GetRepoUsageRequest.new(
        request_options: options
      )

      response = client.get_repo_usage(request: request)
    elsif tab == "runtime"
      request = GetRunnerRuntimeUsageRequest.new(
        request_options: options
      )

      response = client.get_runner_runtime_usage(request: request)
    elsif tab == "runner"
      request = GetRunnerTypeUsageRequest.new(
        request_options: options
      )

      response = client.get_runner_type_usage(request: request)
    else
      tab = "workflows"

      if options.request_type == :REQUEST_TYPE_PERFORMANCE
        request = GetWorkflowPerformanceRequest.new(
          request_options: options
        )

        response = client.get_workflow_performance(request: request)
      else
        request = GetUsageByRepoWorkflowRunnerRequest.new(
          request_options: options
        )

        response = client.get_usage_by_repo_workflow_runner(request: request)
      end
    end

    end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    elapsed_time = (end_time - start_time) * 1_000
    GitHub.logger.info("get_metrics_data complete", {
      "code.namespace" => "Orgs::ActionsMetrics::Controller",
      "code.function" => "get_metrics_data",
      "gh.actions_metrics.controller.get_metrics_data.time" => elapsed_time,
    })
    GitHub.dogstats.distribution("actions_metrics.controller.get_metrics_data.dist.time", elapsed_time)
    result = response.data.to_h

    # line below can be uncommented to generate new test data, should only be done in dev codespace
    # File.write('./test/integration/orgs/actions_metrics/test_data/' + tab + '.txt', result&.to_s)

    process_results(result[:items])

    result[:offset] = params[:offset]
    result[:org] = org&.name
    result[:page_size] = params[:page_size]
    result[:tab] = params[:tab]
    result[:filters] = params[:filters]
    result[:date_range_type] = params[:date_range_type]
    result[:order_by] = params[:order_by]
    result[:request_type] = params[:request_type]
    result[:version] = params[:version]

    result
  end

  def set_param_defaults(params)
    @default_params ||= {
      offset: 0,
      page_size: 10,
      date_range_type: DateRangeType::DATE_RANGE_TYPE_LATEST_MONTH
    }

    params[:offset] ||= @default_params[:offset]
    params[:page_size] ||= @default_params[:page_size]
    params[:filters] ||= @default_params[:filters]
    params[:date_range_type] ||= @default_params[:date_range_type]
  end

  def get_search_query(params)
    params[:q] if params[:q].is_a?(String)
  end

  def get_version(params, user)
    return nil unless T.must(user).employee? # only allow setting version in query param for staff
    params[:version] if params[:version].is_a?(String)
  end

  def get_performance_summary(params, biz, org, repo, user)
    set_param_defaults(params)

    options = RequestOptions.new(
      scope: get_scope(biz, org, repo),
      date_range: params[:date_range_type],
      projection_options: get_projection_options(user, get_version(params, user)),
      custom_date_range: get_custom_date_range(params),
    )

    client = get_client(biz, org, user)
    request = GetPerformanceSummaryRequest.new(
      request_options: options
    )

    response = client.get_performance_summary(request: request).data.to_h
  end

  def get_usage_summary(params, biz, org, repo, user)
    set_param_defaults(params)

    options = RequestOptions.new(
      scope: get_scope(biz, org, repo),
      date_range: params[:date_range_type],
      projection_options: get_projection_options(user, get_version(params, user)),
      custom_date_range: get_custom_date_range(params),
    )

    client = get_client(biz, org, user)
    request = GetUsageSummaryRequest.new(
      request_options: options
    )

    response = client.get_usage_summary(request: request).data.to_h
  end

  def get_scope(biz, org, repo)
    scope_type = ScopeType::SCOPE_TYPE_UNKNOWN
    owner_id = nil
    repo_id = nil

    enterprise_org_ids = nil
    enterprise_id = nil
    enterprise_org_hash = nil

    if !biz.nil?
      # enterprise
      scope_type = ScopeType::SCOPE_TYPE_ENTERPRISE
      enterprise_org_ids = biz.organizations.ids.to_a
      enterprise_id = biz.id
      enterprise_org_hash = get_enterprise_hash(enterprise_org_ids)
    elsif !repo.nil?
      scope_type = ScopeType::SCOPE_TYPE_REPO
      owner_id = repo.owner_id
      repo_id = repo.id
    elsif !org.nil?
      scope_type = ScopeType::SCOPE_TYPE_ORG
      owner_id = org.id
    end


    Scope.new(
      owner_id: owner_id,
      repository_id: repo_id,
      enterprise_orgs: enterprise_org_ids,
      enterprise_id: enterprise_id,
      hash: enterprise_org_hash,
      scope_type: scope_type
    )
  end

  def get_enterprise_hash(orgs)
    OpenSSL::Digest.new("sha256", orgs.join("/")).to_s
  end

  def get_custom_date_range(params)
    custom_date_range = nil
    if params[:custom_date_range] && !params[:custom_date_range].nil? && !params[:custom_date_range][:start].nil? && !params[:custom_date_range][:end].nil?
      custom_date_range = DateRange.new(
        start: {
          seconds: params[:custom_date_range][:start] / 1000,
          nanos: 0,
        },
        end: {
          seconds: params[:custom_date_range][:end] / 1000,
          nanos: 0,
        },
      )
    end

    custom_date_range
  end

  def get_order_by(params)
    order_by = nil
    if params[:order_by] && !params[:order_by].nil?
      order_by = OrderBy.new(field: params[:order_by][:field], direction: params[:order_by][:direction])
    end

    order_by
  end

  def get_filters(params, biz, org)
    filters = get_processed_filters(params[:filters], biz, org)
    proto_filters = filters.map do |filter|
      Filter.new(
        key: filter[:key],
        operator: filter[:operator],
        values: filter[:values]
      )
    end

    proto_filters
  end

  def search_org_repos(org, user, q, user_session: nil)
    if q&.present?
      query = Search::Queries::RepoQuery.new(
        current_user: user,
        phrase: q,
        page: 0,
        sort: %w(updated desc),
        per_page: suggestion_limit,
        user_session: user_session,
        include_forks: true,
        binary_fork_filter: true,
      )

      query.qualifiers[:org].clear.must org.display_login
      query.qualifiers[:user].clear
      query.qualifiers[:owner].clear
      query.qualifiers[:repo].clear

      search = query.execute

      items = search.results.map { |r| r["_model"] }.to_a
      items.map { |r| r.name }
    else
      results = org.visible_repositories_for(user).where(owner_id: org).recently_updated.limit(suggestion_limit)
      repo_names = results.to_a.map { |r| r.name }

      repo_names
    end
  end

  def search_org_workflows(biz, org, user, request_options)
    client = get_client(biz, org, user)

    request = ActionsUsageMetrics::Api::V1::GetWorkflowsRequest.new(
      request_options: request_options
    )

    response = client.get_workflows(request: request)
    response.data.workflows.map { |w| w.file_name }.to_a
  end

  def search_org_jobs(biz, org, user, request_options)
    client = get_client(biz, org, user)

    request = ActionsUsageMetrics::Api::V1::GetJobsRequest.new(
      request_options: request_options
    )

    response = client.get_jobs(request: request)
    response.data.jobs.map { |j| j.job_name }.to_a
  end

  def search_runner_labels(biz, org, user, request_options)
    client = get_client(biz, org, user)

    request = ActionsUsageMetrics::Api::V1::GetRunnerLabelsRequest.new(
      request_options: request_options
    )

    response = client.get_runner_labels(request: request)
    response.data.runner_labels.map { |j| j.runner_label }.to_a
  end

  def get_client(biz, org, user)
    ActionsMetrics::Client.new(biz: biz, org: org, user: user).client
  end

  def suggestion_limit
    8
  end
end
