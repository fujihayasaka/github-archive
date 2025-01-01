# typed: true
# frozen_string_literal: true

module ActionsMetrics::ApiUtils
  include ActionsMetrics::FilterSuggestionsHelper
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

  def get_workflows(params, org, repo, user)
    options = RequestOptions.new(
      scope: get_scope(org, repo),
      limit: limit,
      search: get_search_query(params),
      projection_options: get_projection_options(user, get_version(params, user))
    )

    search_org_workflows(org, options)
  end

  def get_jobs(params, org, repo, user)
    options = RequestOptions.new(
      scope: get_scope(org, repo),
      limit: limit,
      search: get_search_query(params),
      projection_options: get_projection_options(user, get_version(params, user))
    )

    search_org_jobs(org, options)
  end

  def get_runner_labels(params, org, repo, user)
    options = RequestOptions.new(
      scope: get_scope(org, repo),
      limit: limit,
      search: get_search_query(params),
      projection_options: get_projection_options(user, get_version(params, user))
    )

    search_runner_labels(org, options)
  end

  def get_export_status(params, org, repo)
    export_id = params[:export_id]
    client = ActionsMetrics::Client.new(org: org&.name, timeout: 10).client
    response = client.get_export_status(request: GetExportStatusRequest.new(export_id: export_id, scope: get_scope(org, repo)))
    response.data.to_h
  end

  def start_export(params, org, repo, user)
    set_param_defaults(params)
    tab = params[:tab]
    filters = get_processed_filters(params[:filters], org)
    projection_options = get_projection_options(user, get_version(params, user))

    proto_filters = filters.map do |filter|
      Filter.new(
        key: filter[:key],
        operator: filter[:operator],
        values: filter[:values]
      )
    end

    client = ActionsMetrics::Client.new(org: org&.name, timeout: 10).client

    options = RequestOptions.new(
      scope: get_scope(org, repo),
      date_range: params[:date_range_type],
      filters: proto_filters,
      request_type: params[:request_type],
      projection_options: projection_options,
      limit: (2 << 31) - 1, # max int32 - needs this because it defaults to 1000
      offset: 0,
    )

    export_type = ExportType::EXPORT_TYPE_WORKFLOW_USAGE

    if options.request_type == :REQUEST_TYPE_PERFORMANCE
      export_type = ExportType::EXPORT_TYPE_WORKFLOW_PERFORMANCE
    end

    if tab == "jobs"
      export_type = ExportType::EXPORT_TYPE_JOB_USAGE
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

  def get_metrics_data(params, org, repo, user)
    version = get_version(params, user)
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    set_param_defaults(params)
    tab = params[:tab]
    filters = get_processed_filters(params[:filters], org)
    projection_options = get_projection_options(user, version)

    proto_filters = filters.map do |filter|
      Filter.new(
        key: filter[:key],
        operator: filter[:operator],
        values: filter[:values]
      )
    end

    client = ActionsMetrics::Client.new(org: org&.name, timeout: 10).client

    order_by = nil

    if params[:order_by] && !params[:order_by].nil?
      order_by = OrderBy.new(field: params[:order_by][:field], direction: params[:order_by][:direction])
    end

    options = RequestOptions.new(
      scope: get_scope(org, repo),
      offset: params[:offset],
      limit: params[:page_size],
      date_range: params[:date_range_type],
      request_type: params[:request_type],
      filters: proto_filters,
      order_by: order_by,
      projection_options: projection_options,
    )

    if tab == "jobs"
      request = GetJobUsageRequest.new(
        request_options: options
      )

      response = client.get_job_usage(request: request)
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
    if runner_labels_enabled(user)
      return "v3" # labels do not work with v2 of the service so they MUST use v3. This needs to be cleaned up after moving off v2
    end
    return nil unless T.must(user).employee? # only allow setting version in query param for staff
    params[:version] if params[:version].is_a?(String)
  end

  def get_performance_summary(params, org, repo, user)
    set_param_defaults(params)

    options = RequestOptions.new(
      scope: get_scope(org, repo),
      date_range: params[:date_range_type],
      projection_options: get_projection_options(user, get_version(params, user))
    )

    client = ActionsMetrics::Client.new(org: org&.name, timeout: 10).client
    request = GetPerformanceSummaryRequest.new(
      request_options: options
    )

    response = client.get_performance_summary(request: request).data.to_h
  end

  def get_usage_summary(params, org, repo, user)
    set_param_defaults(params)

    options = RequestOptions.new(
      scope: get_scope(org, repo),
      date_range: params[:date_range_type],
      projection_options: get_projection_options(user, get_version(params, user))
    )

    client = ActionsMetrics::Client.new(org: org&.name, timeout: 10).client
    request = GetUsageSummaryRequest.new(
      request_options: options
    )

    response = client.get_usage_summary(request: request).data.to_h
  end

  def get_scope(org, repo)
    scope_type = ScopeType::SCOPE_TYPE_UNKNOWN
    owner_id = nil
    repo_id = nil

    if !repo.nil?
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
      scope_type: scope_type
    )
  end

  def runner_labels_enabled(user)
    user&.feature_enabled?(:actions_usage_metrics_runner_labels)
  end
end
