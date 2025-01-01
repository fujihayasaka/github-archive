# typed: true
# frozen_string_literal: true

# Methods for executing predefined persisted graphql queries identified by id.
module ApplicationController::PersistedGraphqlQueryDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { ApplicationController }

  ALLOWED_ANONYMOUS_QUERIES = T.let(%w[
    AssigneePickerSearchAssignableRepositoryUsersQuery
    ClosedByPullRequestsReferencesQuery
    DependenciesPickerBlockingBlockedByIssuesQuery
    EditHistoryDialogQuery
    HighlightedTimelineQuery
    IssueCommentViewerGhostUserQuery
    IssueIndexPageQuery
    IssueRowSecondaryQuery
    IssueTypePickerQuery
    IssueViewerSecondaryViewQuery
    IssueViewerViewQuery
    LabelPickerQuery
    LabelPickerPermissionQuery
    LabelPickerSearchQuery
    LazyRelationshipsBlockedByListViewQuery
    LazyRelationshipsBlockingListViewQuery
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
    ProjectItemSectionFieldListQuery
    ReactionViewerRelayLazyQuery
    RepositoryLabelIndexPageQuery
    RepositoryMilestonePageQuery
    RepositoryMilestoneQuery
    RepositoryMilestoneIndexPageQuery
    RepositoryMilestoneNewPageQuery
    RepositoryMilestoneEditPageQuery
    IssuesAndPullRequestsCountSecondaryQuery
    SearchPaginatedQuery
    secondaryTimelineQuery
    SubIssuesListItem_NestedSubIssuesQuery
    TimelinePaginationQuery
    TimelinePaginationBackQuery
    TimelinePaginationBackwardQuery
    IssueTypeFilterProviderIssueTypeQuery
    useFetchFilterSuggestedIssueTypesQuery
    useTimelineHighlightQuery
    IssueBodyRefetchQuery
    IssueCommentViewerRefetchQuery
    IssueFieldPickerQuery
  ], T::Array[String])

  def execute_query(
    persisted_query: nil,
    operation_id:,
    variables:,
    referrer_controller_action: nil,
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
      referrer_controller_action: referrer_controller_action,
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
      "is_new_timeline_enabled:true",
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
    if current_user&.feature_flag_enabled?(:persisted_tracer_debug_mode, default: false)
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
