# typed: true
# frozen_string_literal: true

class Api::IssueEvents < Api::App
  include ReceiveSchemaWithOpenApi
  include Api::App::Mysql1ReplicaAuth
  include Api::Issues::EnsureIssuesEnabled
  include Api::Issues::Limits
  include Api::Issues::Preload
  include Api::App::DatabaseConnectionHelper

  # Gate this batch of endpoints on phase2 independently of the always-on
  # default; see Api::App::Mysql1ReplicaAuth.
  def mysql1_replica_auth_flag
    :issues_api_mysql1_replica_auth_phase2
  end

  # Get Events for an Issue
  get "/repositories/:repository_id/issues/:issue_number/events", operation_id: "issues/list-events" do
    replica_clusters = T.let(
      [ApplicationRecord::Mysql1, ApplicationRecord::Repositories, ApplicationRecord::Collab],
      T::Array[T.class_of(ApplicationRecord::Base)],
    )
    with_replica_clusters(replica_clusters, current_user: current_user) do
      repo = find_repo!
      issue = Issues.domain.by_number(int_id_param!(key: :issue_number), repo_id: repo.id).ok
      record_or_404(issue)
      issue = T.cast(issue, Issue)

      set_context_controller_action(issue, "list-events")

      control_access :list_issue_events_for_issue,
        repo: repo,
        resource: issue,
        allow_integrations: true,
        allow_user_via_granular_actor: true

      ensure_issues_enabled_or_pr! repo, issue

      requested_event_types = ::IssueEvent::VALID_EVENTS
      if event_types_to_exclude(repo).include?(:projects)
        requested_event_types -= ::IssueEvent::PROJECT_EVENTS
      end

      if !issue.pull_request?
        requested_event_types -= ::IssueEvent::PULL_REQUEST_EVENTS
      end

      requested_issue_event_type_names = requested_event_types.map do |event_type|
        ::IssueEvent.column_to_platform_type_name(event_type)
      end

      events = Platform::Loaders::Timeline::Placeholders::IssueEvent.load(
        issue.id,
        issue.repository&.id,
        issue.repository&.owner_id,
        current_user,
        visible_events_only: false,
        requested_issue_event_type_names: requested_issue_event_type_names,
      ).then do |placeholders|
        pager = paginate_rel(placeholders.sort_by(&:sort_key))
        Promise.all(pager.map { |placeholder| placeholder.async_value }).then do |values|
          pager.replace(values)
        end
      end.sync # domain-isolation-query-violation:ignore:packages/issues (SELECT)

      IssueEventPrefiller.prefill(events) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      deliver :issue_event_hash, events
    end
  end

  get "/repositories/:repository_id/issues/events", operation_id: "issues/list-events-for-repo" do
    replica_clusters = T.let(
      [ApplicationRecord::Mysql1, ApplicationRecord::Repositories, ApplicationRecord::Collab],
      T::Array[T.class_of(ApplicationRecord::Base)],
    )
    with_replica_clusters(replica_clusters, current_user: current_user) do
      control_access :list_issue_events_for_repo, repo: repo = find_repo!, allow_integrations: true, allow_user_via_granular_actor: true

      cap_paginated_entries!(ISSUES_PULL_REQUESTS_PAGINATION_LIMIT)

      events = filter_partial_access_events(repo, current_user)

      if events
        if repo.has_issues?
          paginated_scope = paginate_rel(events.reorder("issue_events.id DESC")) # domain-isolation-query-violation:ignore:packages/issues (SELECT)

          events = IssueEvent.where("`issue_events`.`id` IN (SELECT * FROM (?) subquery_for_limit)",
                                    paginated_scope.
                                      reorder("issue_events.created_at DESC, issue_events.id DESC").
                                      reselect(:id)).order("issue_events.created_at DESC, issue_events.id DESC")
          events = events.extending(WillPaginate::ActiveRecord::RelationMethods)
          events = T.cast(events, WillPaginate::ActiveRecord::RelationMethods).per_page(paginated_scope.per_page)
          events.current_page = paginated_scope.current_page
          events.total_entries = paginated_scope.total_entries
        else
          events = if FeatureFlag.vexi.enabled?(:issue_events_api_optimized_pr_query, repo, default: false)
            list_pr_events_for_repo_optimized(events)
          else
            list_pr_events_for_repo_legacy(events)
          end
        end
        issues = T.let([], T::Array[Issue])
        options = Api::SerializerOptions.fill(default_options)

        GitHub.dogstats.distribution_time "api.prefill", tags: ["action:issues_events_list"] do
          IssueEventPrefiller.prefill(events, prefill_subject_owners: current_user.try(:using_auth_via_granular_actor?)) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
          issues = issues_for_events(events, repo)
          prefill_for_multiple_issues(issues, options: options) if issues.present? # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        end
        GitHub.dogstats.distribution_time "api.deliver", tags: ["action:issues_events_list"] do
          deliver :issue_event_hash, events, issues: issue_hash_from(issues, repo), filter_project_events: repo.owner.is_a?(User)
        end
      else
        # filter_partial_access_events filtered out all events
        deliver :issue_event_hash, [], issues: {}, filter_project_events: repo.owner.is_a?(User)
      end
    end
  end

  # Get a single Issue Event
  get "/repositories/:repository_id/issues/events/:event_id", operation_id: "issues/get-event" do
    replica_clusters = T.let(
      [ApplicationRecord::Mysql1, ApplicationRecord::Repositories, ApplicationRecord::Collab],
      T::Array[T.class_of(ApplicationRecord::Base)],
    )
    with_replica_clusters(replica_clusters, current_user: current_user) do
      repo = find_repo!
      event = IssueEvents::Public.by_id(int_id_param!(key: :event_id), repository_id: repo.id)
      deliver_error!(404) unless event && event.issue && event.visible_to?(current_user) # domain-isolation-query-violation:ignore:packages/issues (SELECT)

      set_context_controller_action(event.issue, "get-event")

      control_access :get_issue_event,
        repo: repo,
        resource: event,
        allow_integrations: true,
        allow_user_via_granular_actor: true

      ensure_issues_enabled_or_pr! repo, event.issue

      issues = [event.issue]
      IssuePrefiller.prefill(issues)
      Reaction::Summary.prefill(issues)

      deliver :issue_event_hash, event, issues: issue_hash_from(issues, repo), last_modified: calc_last_modified_for_object(event)
    end
  end

  private

  # Filters events for bots with partial access
  #
  # events - An Array of IssueEvent instances.
  # repo   - Repository instance.
  def filter_partial_access_events(repo, current_user)
    allow_issues = allow_pulls = true

    if current_user && current_user.can_have_granular_permissions?
      allow_issues = repo.resources.issues.readable_by?(current_user)
      allow_pulls = repo.resources.pull_requests.readable_by?(current_user)
    elsif current_user && current_user.using_auth_via_granular_actor?
      # Check the "grant". For example an IntegrationInstallation.
      grant = ProgrammaticActor::Grant.with(current_user).with_repository(repo)

      allow_issues = repo.resources.issues.readable_by?(grant)
      allow_pulls = repo.resources.pull_requests.readable_by?(grant)
    end

    events = IssueEvent.where(repository: repo)
    return nil if !allow_issues && !allow_pulls
    return events.pull_requests if !allow_issues
    return events.issues if !allow_pulls

    events
  end

  # Fetches Issues for the given events.
  #
  # events - An Array of IssueEvent instances.
  # repo   - A Repository instance.
  #
  # Returns an issues active record relation.
  def issues_for_events(events, repo)
    issue_ids = events.map { |ev| ev.issue_id }
    issue_ids.uniq!
    issue_ids.compact!
    repo.issues.where(id: issue_ids)
  end

  # Serialize Issues for event endpoints
  #
  # issues - An Array of Issue instances.
  # repo   - A Repository instance.
  #
  # Returns a Hash of ID => <serialized Issue hash>.
  def issue_hash_from(issues, repo)
    return {} if issues.blank?

    serialize_options = {
      repo: repo,
      mime_params: medias.api_params,
      global_id_selection: global_id_selection,
    }

    if (mimes = request.accept).present?
      serialize_options[:accept_mime_types] = mimes
    end

    issues.inject({}) do |memo, issue|
      memo.update issue.id =>
        Api::Serializer.serialize(:issue_hash, issue, serialize_options)
    end
  end

  def event_types_to_exclude(repo)
    [].tap do |types|
      types << :projects unless access_allowed?(:list_projects,
        owner: repo,
        organization: repo.organization,
        resource: repo,
        allow_integrations: true,
        allow_user_via_granular_actor: true)
    end
  end

  # Legacy query path for listing PR events when issues are disabled.
  # Uses FORCE INDEX on (repository_id, issue_id, event) and JOINs issues
  # table via .pull_requests scope, with issue_events as the driver table.
  def list_pr_events_for_repo_legacy(events)
    events = events.from([Arel.sql("`#{IssueEvent.table_name}` FORCE INDEX (index_issue_events_on_repo_id_issue_id_and_event)")])
    events = events.pull_requests
    # here we use different join strategies for the count and the page load.
    # for the count, we add an extra restriction to issues so that issues can be used efficiently as driver table
    # while for the page load we continue to use issue_events as the driver table
    relation = events.reorder("issue_events.id DESC").limit(pagination[:per_page]).page(pagination[:page])

    relation = IssueEvent.from("(#{relation.select("issue_events.id").to_sql}) AS subquery")
      .joins("JOIN issue_events ON issue_events.id = subquery.id")
      .order("issue_events.id DESC")

    relation = relation.limit(pagination[:per_page]).page(nil) # need to call .page(nil) in order to include pagination methods like .total_entries
    relation.total_entries = events.unscoped.from(
      events.unscope(:order, :select, :from).select("1 as one").
        where("issues.repository_id = issue_events.repository_id").
        limit(pagination[:total_entries])
    ).count # domain-isolation-query-violation:ignore:packages/issues (SELECT)

    relation
  end

  def list_pr_events_for_repo_optimized(events)
    # Order by created_at DESC, id DESC so that the optimizer can use the
    # (repository_id, created_at) index for a backward index scan instead of
    # filesorting all >18M rows when ordering by id DESC alone.
    events = events.pull_requests
    # here we use different join strategies for the count and the page load.
    # for the count, we add an extra restriction to issues so that issues can be used efficiently as driver table
    # while for the page load we continue to use issue_events as the driver table
    relation = events.reorder("issue_events.created_at DESC, issue_events.id DESC").limit(pagination[:per_page]).page(pagination[:page])

    relation = IssueEvent.from("(#{relation.select("issue_events.id").to_sql}) AS subquery")
      .joins("JOIN issue_events ON issue_events.id = subquery.id")
      .order("issue_events.created_at DESC, issue_events.id DESC")

    relation = relation.limit(pagination[:per_page]).page(nil) # need to call .page(nil) in order to include pagination methods like .total_entries
    relation.total_entries = events.unscoped.from(
      events.unscope(:order, :select, :from).select("1 as one").
        where("issues.repository_id = issue_events.repository_id").
        limit(pagination[:total_entries])
    ).count # domain-isolation-query-violation:ignore:packages/issues (SELECT)

    relation
  end
end
