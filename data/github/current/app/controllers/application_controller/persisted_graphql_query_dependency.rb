# typed: true
# frozen_string_literal: true

# Methods for executing predefined persisted graphql queries identified by id.
module ApplicationController::PersistedGraphqlQueryDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { ApplicationController }

  ALLOWED_ANONYMOUS_QUERIES = T.let(%w[
    AssigneePickerSearchAssignableRepositoryUsersWithQuery
    AssigneePickerSearchAssignableRepositoryUsersWithLoginsQuery
    ClosedByPullRequestsReferencesQuery
    EditHistoryDialogQuery
    HighlightedTimelineQuery
    IssueCommentViewerGhostUserQuery
    IssueIndexPageQuery
    IssueRowSecondaryQuery
    IssueTypePickerQuery
    IssueViewerSecondaryViewQuery
    IssueViewerViewQuery
    LabelPickerQuery
    LabelPickerSearchQuery
    MarkdownEditHistoryViewerQuery
    useMarkdownEditHistoryViewerQueryQuery
    MilestonePickerQuery
    MilestonePickerSearchQuery
    NewTimelinePaginationBackQuery
    NewTimelinePaginationFrontQuery
    NewTimelinePaginationHighlightQuery
    OpenClosedTabsQuery
    ParticipantsListQuery
    ProjectPickerQuery
    SearchPaginatedQuery
    SubIssuesListItem_NestedSubIssuesQuery
    TimelinePaginationQuery
    TimelinePaginationBackQuery
    TimelinePaginationBackwardQuery
    typeFilterIssueTypeQuery
    useFetchFilterSuggestedIssueTypesQuery
    useTimelineHighlightQuery
    IssueBodyRefetchQuery
  ], T::Array[String])

  def queries_to_preload(matching_url_pattern: nil)
    GitHub.route_query_mapper.fetch(matching_url_pattern[:url])
  end

  def matching_url_pattern(path_override = nil)
    GitHub.route_query_mapper.get_matching_url_pattern(path_override || request&.path)
  end

  def query_variables(query_id:, matching_url_pattern:, variable_overwrite_fn:)
    # get the variables name and types for the current query
    variable_types = GitHub.route_query_mapper.fetch_variables(query_id)

    # map path parameter named captures to their graphql types
    path_variables = {}
    variable_types.each do |variable_name, variable_type|
      next unless matching_url_pattern[:named_captures].key?(variable_name)
      value = matching_url_pattern[:named_captures][variable_name]
      path_variables[variable_name] = case variable_type
      when "Int", "Int!"
        value.to_i
      when "Boolean", "Boolean!"
        value == "true"
      else
        value
      end
    end

    # allow the caller to override the variables as well as add more
    unsorted_variables = if !variable_overwrite_fn.nil?
      variable_overwrite_fn.call(path_variables)
    else
      path_variables
    end

    unsorted_variables.with_indifferent_access.sort_by(&:first).to_h
  end

  def compute_preloaded_queries(
    variable_overwrite_fns: {},
    tags: [],
    path_override: nil,
    precompute_subscription_fns: {},
    origin: nil,
    run_defer_directive: false,
    is_hard_navigation: false,
    add_query_time_tags_fn: nil
  )
    # check if the current path has matching queries in the routes
    matching_url_pattern = matching_url_pattern(path_override)

    return nil if matching_url_pattern.nil?

    variable_overwrite_fn = variable_overwrite_fns[matching_url_pattern[:url]]
    precompute_subscription_fn = precompute_subscription_fns[matching_url_pattern[:url]]
    preloaded_subscriptions = T.let(nil, T.nilable(Hash))

    preloaded_query_gql_objects = []

    queries = queries_to_preload(matching_url_pattern:)

    execute_preloaded_start = Timer.start
    preloaded_queries = queries.map do |query_id|
      scope = request&.GET.fetch("scope", nil)
      variables = query_variables(query_id:, matching_url_pattern:, variable_overwrite_fn:)

      result = execute_query(
        operation_id: query_id,
        variables:,
        performance_trace: false,
        reporting_tags: tags,
        scope:,
        origin:,
        run_defer_directive: run_defer_directive,
        is_hard_navigation: is_hard_navigation,
        add_query_time_tags_fn: add_query_time_tags_fn
      )

      query_timing_data = result.tracker.nil? ? {} : result.tracker.timing_data

      result_hash = result.to_h

      # Dont allow overriding the preloaded_subscriptions
      if !precompute_subscription_fn.nil? && preloaded_subscriptions.blank?
        preloaded_subscriptions = precompute_subscription_fn.call(query_id, result_hash)
      end

      preloaded_query_gql_objects << result

      {
        queryId: query_id,
        queryName: result.query.context[:query_name],
        variables: variables,
        result: result_hash,
        timestamp: Time.now.to_i,
        timing_data: query_timing_data
      }
    end
    execute_preloaded_start.stop

    GitHub.dogstats.distribution("request.ssr.preloaded_queries_execution.time", execute_preloaded_start.elapsed_ms, tags: tags)

    {
      preloaded_queries: preloaded_queries,
      preloaded_subscriptions: preloaded_subscriptions || {},
      preloaded_query_gql_objects: preloaded_query_gql_objects
    }
  end

  def execute_query(
    persisted_query: nil,
    operation_id:,
    variables:,
    performance_trace: false,
    scope: nil,
    reporting_tags: [],
    scope_object: nil,
    subscription_topic: nil,
    origin: nil,
    enforce_read_only: false,
    block_mutations: false,
    run_defer_directive: false,
    is_hard_navigation: false,
    add_query_time_tags_fn: nil
  )
    # Authorization logic is not properly applied when using ORIGIN_INTERNAL.
    # ORIGIN_API with scopes disabled does correctly enforce authorization.
    # Override to a different value only if authorization happens before that in the request flow.
    origin ||= Platform::ORIGIN_API

    context = {
      viewer: current_user,
      session: T.unsafe(self).session,
      user_session: T.unsafe(self).user_session,
      rails_request: request,
      enforce_conditional_access_via_graphql: true,
      request_access_security_header: request&.env[EnterpriseManagedUsersHelper::ENTERPRISE_ACCESS_HEADER],
      origin: origin,
      is_relay_request: true,
      controller: T.unsafe(self).controller_name,
      action: T.unsafe(self).action_name,
      is_internal_graphql: true,
      cap_filter: T.unsafe(self).cap_filter,
      performance_trace: performance_trace,
      reporting_tags: reporting_tags,
      authenticated_actor_using_web_session: true,
      run_defer_directive: run_defer_directive,
      anonymous_viewer_query_allowlist: ALLOWED_ANONYMOUS_QUERIES,
    }

    if defined?(set_scoped_repo_id) && T.unsafe(self).send(:set_scoped_repo_id) && defined?(current_repository) && (current_repo = T.unsafe(self).send(:current_repository)).present?
      context[:scoped_repo_id] = current_repo.id
    end

    if !scope.nil?
      context[:scope] = scope
    end

    if !scope_object.nil?
      context[:scope_object] = scope_object.transform_keys(&:to_sym)
    end
    # pass nil since the query is loaded from the context via the operation id
    query_text = nil
    context[:operation_id] = operation_id
    validate = should_validate_query?

    execution_start = GitHub::Dogstats.monotonic_time

    result = Platform.execute(
      query_text,
      target: :internal,
      variables:,
      context: context,
      raise_exceptions: false,
      request_env: request&.env,
      validate:,
      subscription_topic: subscription_topic,
      enforce_read_only: enforce_read_only,
      block_mutations: block_mutations,
    )

    operation_name = ""
    sucess = false
    if result.respond_to?(:success?) && result.success?
      success = true
      query = T.unsafe(result).query
      operation_name = query.operation_name
      total_time = 0
      is_staff = current_user&.employee? ? true : false

      if query&.current_trace&.respond_to?(:stats) && query&.current_trace.stats
        stats = query.current_trace.stats

        stats.each do |type_name, metrics|
          tags = ["type:#{type_name}", "query:#{query.operation_name}", "soft:#{!is_hard_navigation}", "staff:#{is_staff}"]
          time = metrics[:time]
          count = metrics[:count]
          paths = metrics[:paths]
          total_time += time

          GitHub.dogstats.distribution("request.persisted_query.authorized.time", time, tags: tags)
          GitHub.dogstats.count("request.persisted_query.authorized.count", count, tags: tags)

          paths.each do |path, path_count|
            new_tags = tags + ["path:#{path}"]
            GitHub.dogstats.count("request.persisted_query.authorized.path.count", path_count, tags: new_tags)
          end
        end

        GitHub.dogstats.distribution("request.persisted_query.authorized.total_time", total_time, tags: ["query:#{query.operation_name}", "soft:#{!is_hard_navigation}", "staff:#{is_staff}"])
      end
    end

    query_time_tags = [
      "query:#{operation_name}",
      "is_running_experiment:#{is_running_experiment?}",
      "logged_in:#{current_user ? true : false}",
      "success:#{success}",
      "is_new_timeline_enabled:#{current_user&.feature_enabled?(:issues_react_new_timeline)}",
    ]

    if add_query_time_tags_fn && success && result.respond_to?(:data)
      extra_tags = add_query_time_tags_fn.call(operation_name, result.data)
      query_time_tags.concat(extra_tags) if extra_tags
    end

    GitHub.dogstats.distribution("request.persisted_query.execute_query.dist.time", GitHub::Dogstats.monotonic_time - execution_start, tags: query_time_tags)

    if T.unsafe(result).query.subscription? && T.unsafe(result).query.context[:subscription_id].present?
      T.unsafe(self).response.add_header("Access-Control-Expose-Headers", "X-Subscription-ID")
      T.unsafe(self).response.add_header("X-Subscription-ID", T.unsafe(result).query.context[:subscription_id])
    end

    result
  end

  def is_running_experiment?
    if current_user&.feature_enabled?(:persisted_tracer_debug_mode)
      true
    else
      false
    end
  end

  private

  def should_validate_query?
    return @should_validate if defined?(@should_validate)

    # return true if the flag is off so validation are running
    @should_validate = false
  end
end
