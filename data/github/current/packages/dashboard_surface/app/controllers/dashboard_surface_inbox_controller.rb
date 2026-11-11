# typed: strict
# frozen_string_literal: true

require "react_payload"

class DashboardSurfaceInboxController < ApplicationController
  before_action :login_required
  before_action :ensure_pulls_dashboard_inbox_enabled

  skip_before_action :perform_conditional_access_checks # rubocop:todo GitHub/DoNotSkipCapBeforeAction


  depends_on_clusters ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Pages,
    ApplicationRecord::Repositories,
    only: [:index, :queries]

  depends_on_clusters ApplicationRecord::NotificationsEntries,
    optional: true, only: [:index, :queries]

  depends_on_clusters ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql1,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Repositories,
    only: [:deferred]

  class DashboardSurfaceInboxRoutePayload < ReactPayload::Base
    sig { override.returns(String) }
    def route_id
      "pullsInboxSurfaceContentRoute"
    end

    sig do
      params(
        results: T::Array[PullRequest],
        pagination: DashboardSurfaceController::Pagination,
        categories_by_pr_id: T::Hash[Integer, String],
      ).void
    end
    def initialize(results, pagination, categories_by_pr_id)
      @results = results
      @pagination = pagination
      @categories_by_pr_id = categories_by_pr_id
    end

    sig { override.returns(T::Hash[String, T.untyped]) }
    def payload
      DashboardSurface::Payloads::SearchResults.serialize(
        @results,
        @pagination,
        @categories_by_pr_id,
      )
    end
  end

  class DashboardSurfaceInboxRouteDeferredPayload < ReactPayload::Base
    sig { override.returns(String) }
    def route_id
      "pullsInboxSurfaceContentDeferredData"
    end

    sig { params(results: DashboardSurface::Loaders::ResultsLoader::DeferredData).void }
    def initialize(results)
      @results = results
    end

    sig { override.returns(T::Hash[String, T.untyped]) }
    def payload
      DashboardSurface::Payloads::InboxSearchResultsDeferredContent.serialize(@results)
    end
  end

  sig { void }
  def index
    context_region_title "Pull Requests"

    layout_payload = build_layout_payload
    respond_with_react(
      title: "Pull Requests",
      app_name: "dashboard-surface",
      payload: layout_payload,
      nested_payloads: -> { [layout_payload] },
      custom_tags: [
        "referrer_controller_action:pull_requests#dashboard",
        "is_react:true",
      ],
      app_payload_generator: -> {
        global_sso_app_payload.merge(
          current_user: DashboardSurface::Payloads::CurrentUser.serialize(current_user),
          inboxSectionQueries: inbox_section_queries,
          filters: { maxPrAge: current_user_max_pr_age },
        )
      },
    )
  end

  sig { void }
  def queries # rubocop:disable GitHub/UseRestfulActions
    context_region_title "Pull Requests"

    query_config = DashboardSurface::Models::InboxSearchConfig.from_params(params, current_user)
    issues, total_count, categories_by_issue_id = find_issues(query_config)
    results = DashboardSurface::Loaders::ResultsLoader.main_content_from(
      issues: issues,
      current_user:,
    )

    categories_by_pr_id = issues.each_with_object({}) do |issue, hash|
      next if issue.pull_request_id.nil?

      category = categories_by_issue_id[issue.id]
      next if category.nil?

      hash[issue.pull_request_id] = category
    end

    payload = DashboardSurfaceInboxRoutePayload.new(
      results,
      DashboardSurfaceController::Pagination.new(
        current_page: 1,
        total_pages: 1,
        total_count: results.length,
      ),
      categories_by_pr_id,
    )

    respond_with_react(
      payload: payload,
      title: "Pull Requests",
      app_name: "dashboard-surface",
      nested_payloads: -> { [build_layout_payload] },
      custom_tags: [
        "referrer_controller_action:pull_requests#dashboard",
        "is_react:true",
      ],
      app_payload_generator: -> {
        global_sso_app_payload.merge(
          current_user: DashboardSurface::Payloads::CurrentUser.serialize(current_user),
          inboxSectionQueries: inbox_section_queries,
          filters: { maxPrAge: current_user_max_pr_age },
        )
      },
    )
  end

  sig { void }
  def deferred # rubocop:disable GitHub/UseRestfulActions
    issues = if params[:pr_ids].present?
      load_authorized_issues_from_pr_ids(Array(params[:pr_ids]).map(&:to_i))
    else
      query_config = DashboardSurface::Models::InboxSearchConfig.from_params(params, current_user)
      found_issues, _total_count, _categories = find_issues(query_config)
      found_issues
    end

    results_data = DashboardSurface::Loaders::ResultsLoader.deferred_content_from(issues: issues, current_user:)
    payload = DashboardSurfaceInboxRouteDeferredPayload.new(results_data)

    respond_with_react(
      payload: payload,
      title: "Pull Requests",
      app_name: "dashboard-surface",
      nested_payloads: -> { [build_layout_payload] },
    )
  end

  sig { returns(DashboardSurfaceController::DashboardSurfaceLayoutPayload) }
  private def build_layout_payload
    DashboardSurfaceController::DashboardSurfaceLayoutPayload.new(get_compact_mode_setting, get_saved_views, DashboardSurface::Payloads::SidebarLinks.links(current_user), global_sso_app_payload)
  end

  sig { returns(T::Boolean) }
  private def get_compact_mode_setting
    current_user ? current_user.settings.get(:dashboard_surface_compact_mode) : false
  end

  sig { returns(String) }
  private def current_user_max_pr_age
    pref = current_user&.settings&.get(:pulls_inbox_max_pr_age).presence
    return DashboardSurface::Models::InboxSearchConfig::DEFAULT_MAX_PR_AGE unless pref

    DashboardSurface::Models::InboxSearchConfig::PR_AGE_OPTIONS.key?(pref) ? pref : DashboardSurface::Models::InboxSearchConfig::DEFAULT_MAX_PR_AGE
  end

  sig { returns(T::Hash[String, String]) }
  private def inbox_section_queries
    map = DashboardSurface::Models::InboxSections.query_map
    unless FeatureFlag.vexi.enabled?(:team_review_requested_by_user_filter, current_user, default: false)
      map = map.except("team-review-requested")
    end
    map
  end

  sig { returns(T::Array[DashboardSurface::Payloads::SavedView]) }
  private def get_saved_views
    DashboardSurface::Loaders::SavedViewLoader.load_for_user(
      current_user,
      DashboardSurface::Loaders::SavedViewLoader::SearchType::PullRequests,
    )
  end

  sig do
    params(query_config: DashboardSurface::Models::InboxSearchConfig)
      .returns([T::Array[Issue], Integer, T::Hash[Integer, String]])
  end
  private def find_issues(query_config)
    query_config.es_queries.each do |q|
      if q.include?("is:issue")
        GitHub.dogstats.increment("search.advanced_search.includes_is_issue")
      end
    end

    issues, total_count, categories_by_issue_id = if query_config.composite?
      find_composite_issues(query_config)
    else
      search_results = execute_search(
        phrase: query_config.es_query,
        page: query_config.page,
        per_page: query_config.maximum_result_limit,
      )
      categories_by_issue_id = T.let({}, T::Hash[Integer, String])
      category = category_for_named_section(query_config.named_section)
      if category
        search_results.models.each do |issue|
          categories_by_issue_id[issue.id] = category
        end
      end
      [search_results.models, search_results.models.length, categories_by_issue_id]
    end

    filter = query_config.post_filter
    if filter
      issues = apply_post_filter(filter, issues)
      total_count = issues.length
    end

    [issues, total_count, categories_by_issue_id]
  end

  sig do
    params(query_config: DashboardSurface::Models::InboxSearchConfig)
      .returns([T::Array[Issue], Integer, T::Hash[Integer, String]])
  end
  private def find_composite_issues(query_config)
    limit = query_config.maximum_result_limit

    es_queries = query_config.es_queries
    all_results = es_queries.map do |phrase|
      execute_search(
        phrase: phrase,
        page: query_config.page,
        per_page: limit,
      )
    end

    seen_ids = T.let(Set.new, T::Set[Integer])
    deduplicated_issues = T.let([], T::Array[Issue])
    categories_by_issue_id = T.let({}, T::Hash[Integer, String])

    all_results.each_with_index do |search_results, index|
      category = category_for_named_query(T.must(es_queries[index]))

      search_results.models.each do |issue|
        next if seen_ids.include?(issue.id)

        seen_ids.add(issue.id)
        deduplicated_issues << issue
        categories_by_issue_id[issue.id] = category if category
      end
    end

    deduplicated_issues = deduplicated_issues
      .sort_by { |issue| [issue.updated_at&.to_i || 0, issue.id] }
      .reverse
      .first(limit)

    total_count = deduplicated_issues.length

    [deduplicated_issues, total_count, categories_by_issue_id]
  end

  sig { params(phrase: String).returns(T.nilable(String)) }
  private def category_for_named_query(phrase)
    normalized_phrase = [
      DashboardSurface::Models::SearchConfig::NEEDS_ACTION_CHANGES_REQUESTED_QUERY,
      DashboardSurface::Models::SearchConfig::NEEDS_ACTION_FAILING_CHECKS_QUERY,
      DashboardSurface::Models::SearchConfig::NEEDS_ACTION_AGENT_BLOCKED,
      DashboardSurface::Models::SearchConfig::NEEDS_ACTION_ACTIVE_REVIEW_QUERY,
    ].find { |candidate| phrase == candidate || phrase.start_with?("#{candidate} ") }

    case normalized_phrase
    when DashboardSurface::Models::SearchConfig::NEEDS_ACTION_CHANGES_REQUESTED_QUERY
      "CHANGES_REQUESTED"
    when DashboardSurface::Models::SearchConfig::NEEDS_ACTION_FAILING_CHECKS_QUERY
      "CI_FAILING"
    when DashboardSurface::Models::SearchConfig::NEEDS_ACTION_AGENT_BLOCKED, DashboardSurface::Models::SearchConfig::NEEDS_ACTION_ACTIVE_REVIEW_QUERY
      "AWAITING_REVIEW"
    end

  end

  sig { params(section: T.nilable(String)).returns(T.nilable(String)) }
  private def category_for_named_section(section)
    case section
    when "ready-to-merge"
      "READY_TO_MERGE"
    when "review-requested", "team-review-requested"
      "AWAITING_REVIEW"
    when "merge-queue"
      "MERGE_QUEUE"
    end
  end

  sig { params(pr_ids: T::Array[Integer]).returns(T::Array[Issue]) }
  private def load_authorized_issues_from_pr_ids(pr_ids)
    return [] if pr_ids.empty? || current_user.nil?

    issue_ids = Issue.where(pull_request_id: pr_ids).pluck(:id)
    return [] if issue_ids.empty?

    visible_ids = Issue.legacy_visible_ids_for(issue_ids, viewer: current_user)
    Issue.where(id: visible_ids).to_a
  end

  sig { params(phrase: String, page: Integer, per_page: Integer).returns(Search::Results[T.untyped]) }
  private def execute_search(phrase:, page:, per_page:)
    Search::Queries::ConditionalIssueQuery.new(
     allow_insecure_user_to_server_app_query: false,
     current_user: current_user,
     user_session: user_session,
     remote_ip: request&.remote_ip,
     phrase: phrase,
     page: page,
     per_page: per_page,
     source_fields: false,
     ngram_title: true,
     index: ::Elastomer::Indexes::Issues.by_type("pr"),
     context: "#{self.class.name&.demodulize&.underscore}-find_issues",
    ).execute
  end

  sig { void }
  private def ensure_pulls_dashboard_inbox_enabled
    render_404 unless FeatureFlag.vexi.enabled?(:pulls_dashboard_inbox, current_user, default: false)
  end

  sig { params(filter: Symbol, issues: T::Array[Issue]).returns(T::Array[Issue]) }
  private def apply_post_filter(filter, issues)
    case filter
    when :post_filter_ready_to_merge
      post_filter_ready_to_merge(issues)
    else
      issues
    end
  end

  sig { params(issues: T::Array[Issue]).returns(T::Array[Issue]) }
  private def post_filter_ready_to_merge(issues)
    return issues if issues.empty?

    IssuePrefiller.prefill(issues, only_prefill: [:pull_request], current_user: current_user)

    issues.select do |issue|
      pr = issue.pull_request
      next false unless pr
      next false if pr.draft? || pr.closed? || pr.merged?

      merge_requirements = PullRequest::MergeRequirements.new(
        pr,
        nil,
        nil,
        nil,
        current_user,
        skip_enqueue_mergeable_update: true
      )

      merge_requirements.state == :mergeable
    end
  end
end
