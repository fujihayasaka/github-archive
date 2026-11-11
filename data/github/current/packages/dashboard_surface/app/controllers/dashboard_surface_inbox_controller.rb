# typed: strict
# frozen_string_literal: true

require "react_payload"

class DashboardSurfaceInboxController < ApplicationController
  include DashboardHelper
  include Pulls::OpenStateClosedByPrefillExclusion
  before_action :login_required
  around_action :measure_inbox_request, only: %i[index queries deferred]

  # Sections whose results may be relabeled `MERGE_CONFLICTS`.
  MERGE_CONFLICT_OVERRIDE_SECTIONS = T.let(
    Set["needs-action", "waiting-for-review"].freeze,
    T::Set[String],
  )

  # Gate-level CAP enforcement is not applicable because this controller
  # is not scoped to a single organization. Results are filtered inline
  # via cap_filter.authorized_resources instead.
  CAP_OPT_OUT_ACTIONS = T.let(%w(index queries deferred).freeze, T::Array[String])

  depends_on_clusters ApplicationRecord::Authnd,
    ApplicationRecord::Collab,
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

  global_navigation_title "Pull requests", only: [:index, :queries]

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
        viewer: T.nilable(User),
      ).void
    end
    def initialize(results, pagination, categories_by_pr_id, viewer: nil)
      @results = results
      @pagination = pagination
      @categories_by_pr_id = categories_by_pr_id
      @viewer = viewer
    end

    sig { override.returns(T::Hash[String, T.untyped]) }
    def payload
      DashboardSurface::Payloads::SearchResults.serialize(
        results: @results,
        pagination: @pagination,
        categories_by_pr_id: @categories_by_pr_id,
        viewer: @viewer,
      )
    end
  end

  # Legacy SSR-blocking preload used when the customize-sections feature is
  # off. Always represents the `review-requested` section and uses the static
  # route id `sectionReviewRequested` that the existing frontend expects.
  #
  # TODO(pull_request_inbox_customize_sections rollout): delete this class
  # once the flag is fully launched. `SectionBlockingPayload` (with route id
  # `sectionReviewRequestedBlocking`) covers the same case dynamically.
  class SectionReviewRequestedPayload < ReactPayload::Base
    sig { override.returns(String) }
    def route_id
      "sectionReviewRequested"
    end

    sig do
      params(
        results: T::Array[PullRequest],
        total_count: Integer,
        categories_by_pr_id: T::Hash[Integer, String],
        viewer: T.nilable(User),
      ).void
    end
    def initialize(results, total_count, categories_by_pr_id, viewer: nil)
      @results = results
      @total_count = total_count
      @categories_by_pr_id = categories_by_pr_id
      @viewer = viewer
    end

    sig { override.returns(T::Hash[String, T.untyped]) }
    def payload
      {
        results: @results.map do |result|
          DashboardSurface::Payloads::PullRequestResult.serialize(result, category: @categories_by_pr_id[result.id], viewer: @viewer)
        end,
        totalCount: @total_count,
      }
    end
  end

  # SSR-blocking preload for a single inbox section. Emitted only when the
  # customize-sections feature is on so the new frontend path can dispatch on
  # the dynamic `section{Id}Blocking` route id.
  class SectionBlockingPayload < ReactPayload::Base
    sig { override.returns(String) }
    def route_id
      "section#{@section_id.split("-").map(&:capitalize).join}Blocking"
    end

    sig do
      params(
        section_id: String,
        results: T::Array[PullRequest],
        total_count: Integer,
        categories_by_pr_id: T::Hash[Integer, String],
        viewer: T.nilable(User),
      ).void
    end
    def initialize(section_id, results, total_count, categories_by_pr_id, viewer: nil)
      # route_id is interpolated from @section_id, so reject
      # anything that isn't a registered section before we construct.
      raise ArgumentError, "unknown section id: #{section_id.inspect}" unless DashboardSurface::Models::InboxSections.named_query?(section_id)
      @section_id = section_id
      @results = results
      @total_count = total_count
      @categories_by_pr_id = categories_by_pr_id
      @viewer = viewer
    end

    sig { override.returns(T::Hash[String, T.untyped]) }
    def payload
      {
        results: @results.map do |result|
          DashboardSurface::Payloads::PullRequestResult.serialize(result, category: @categories_by_pr_id[result.id], viewer: @viewer)
        end,
        totalCount: @total_count,
      }
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
    layout_payload = build_layout_payload
    section_payloads = build_index_section_payloads(first_visible_section_id)
    respond_with_react(
      title: "Pull requests",
      app_name: "dashboard-surface",
      payload: T.must(section_payloads.first),
      nested_payloads: -> { [layout_payload] + section_payloads.drop(1) },
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
    query_config = DashboardSurface::Models::InboxSearchConfig.from_params(params, current_user)
    results, _total_count, categories_by_pr_id = load_pull_request_results(query_config)

    payload = DashboardSurfaceInboxRoutePayload.new(
      results,
      DashboardSurfaceController::Pagination.new(
        current_page: 1,
        total_pages: 1,
        total_count: results.length,
      ),
      categories_by_pr_id,
      viewer: current_user,
    )

    respond_with_react(
      payload: payload,
      title: "Pull requests",
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
    results_data = begin
      issues = if params[:pr_ids].present?
        load_authorized_issues_from_pr_ids(Array(params[:pr_ids]).map(&:to_i))
      else
        query_config = DashboardSurface::Models::InboxSearchConfig.from_params(params, current_user)
        found_issues, _total_count, _categories = find_issues(query_config)
        found_issues
      end

      DashboardSurface::Loaders::ResultsLoader.deferred_content_from(issues: cap_filtered(issues), current_user:)
    rescue => e
      GitHub.logger.warn("Failed to load deferred content for Inbox: #{e.message}")
      GitHub.dogstats.increment("dashboard_surface.deferred_content.failed", tags: ["inbox"])
      DashboardSurface::Loaders::ResultsLoader::DeferredData.empty
    end

    payload = DashboardSurfaceInboxRouteDeferredPayload.new(results_data)
    respond_with_react(
      payload: payload,
      title: "Pull requests",
      app_name: "dashboard-surface",
      nested_payloads: -> { [build_layout_payload] },
    )
  end

  # Builds the SSR-blocking preloads for the inbox page.
  #
  # When the customize-sections feature is off we always emit the legacy
  # `SectionReviewRequestedPayload` (route id `sectionReviewRequested`) so the
  # existing frontend keeps working unchanged. When it's on, emit the dynamic
  # blocking payload for the user's first visible section so the initial visible
  # section has data inline.
  #
  # TODO(pull_request_inbox_customize_sections rollout): once the flag is
  # fully launched, drop the flag check and return only the dynamic first-section
  # payload.
  sig { params(section_id: String).returns(T::Array[ReactPayload::Base]) }
  private def build_index_section_payloads(section_id)
    unless customize_sections_enabled?
      return [build_legacy_review_requested_payload]
    end

    first_section_id = section_id_for_first_payload(section_id)
    [build_section_blocking_payload(first_section_id)]
  end

  sig { params(section_id: String).returns(SectionBlockingPayload) }
  private def build_section_blocking_payload(section_id)
    section_id = section_id_for_first_payload(section_id)
    section_params = params.merge(
      filter: [section_id, repo_scope_from_filter].reject(&:blank?).join(" "),
      max_pr_age: current_user_max_pr_age,
    )
    query_config = DashboardSurface::Models::InboxSearchConfig.from_params(section_params, current_user)
    results, total_count, categories_by_pr_id = load_pull_request_results(query_config)

    SectionBlockingPayload.new(section_id, results, total_count, categories_by_pr_id, viewer: current_user)
  end

  sig { returns(SectionReviewRequestedPayload) }
  private def build_legacy_review_requested_payload
    section_params = params.merge(
      filter: [DEFAULT_FIRST_SECTION, repo_scope_from_filter].reject(&:blank?).join(" "),
      max_pr_age: current_user_max_pr_age,
    )
    query_config = DashboardSurface::Models::InboxSearchConfig.from_params(section_params, current_user)
    results, total_count, categories_by_pr_id = load_pull_request_results(query_config)

    SectionReviewRequestedPayload.new(results, total_count, categories_by_pr_id, viewer: current_user)
  rescue => e
    GitHub.logger.warn("DashboardSurfaceInboxController#build_review_requested_payload failed: #{e.message}")
    GitHub.dogstats.increment("dashboard_surface.inbox.build_review_requested_payload.failed")
    Failbot.report(e)
    SectionReviewRequestedPayload.new([], 0, {}, viewer: current_user)
  end

  sig { params(section_id: String).returns(String) }
  private def section_id_for_first_payload(section_id)
    return DEFAULT_FIRST_SECTION unless customize_sections_enabled?
    return section_id if inbox_section_queries.key?(section_id)

    # Keep the blocking payload aligned with the renderable section list even if
    # a caller passes a stale, hidden, or feature-gated section id.
    fallback_section_id = inbox_section_queries.keys.first
    raise "No available inbox sections for dynamic preload" if fallback_section_id.nil?
    fallback_section_id
  end

  # The section id whose data we should inline as the SSR-blocking preload.
  # Mirrors the frontend's `computeFirstVisibleInboxSection`:
  #   1. Pick the first section in the user's order that is currently visible
  #   2. Otherwise fall back to the first visible available section, or
  #      `"review-requested"` as a last resort
  # When the customize-sections feature is off we always preload
  # `"review-requested"`, matching pre-feature behavior.
  DEFAULT_FIRST_SECTION = "review-requested"

  sig { returns(String) }
  private def first_visible_section_id
    return DEFAULT_FIRST_SECTION unless customize_sections_enabled?

    available = inbox_section_queries.keys
    return DEFAULT_FIRST_SECTION if available.empty?

    ordered_available = get_section_order_setting & available
    ordered_available.first || T.must(available.first)
  end

  sig do
    params(query_config: DashboardSurface::Models::InboxSearchConfig)
      .returns([T::Array[PullRequest], Integer, T::Hash[Integer, String]])
  end
  private def load_pull_request_results(query_config)
    issues, total_count, categories_by_issue_id = find_issues(query_config)
    exclude_prefills = T.let([], T::Array[Symbol])
    if exclude_closed_by_prefill_for_open_state_query?(query_config.es_query)
      exclude_prefills = [:closed_by]
    end

    filtered_issues = cap_filtered(issues)
    results = DashboardSurface::Loaders::ResultsLoader.main_content_from(
      issues: filtered_issues,
      current_user:,
      exclude_prefills: exclude_prefills,
    )

    categories_by_pr_id = filtered_issues.each_with_object({}) do |issue, hash|
      next if issue.pull_request_id.nil?

      category = categories_by_issue_id[issue.id]
      next if category.nil?

      hash[issue.pull_request_id] = category
    end

    [results, total_count, categories_by_pr_id]
  end

  sig { returns(DashboardSurfaceController::DashboardSurfaceLayoutPayload) }
  private def build_layout_payload
    selected_repos = DashboardSurface::Loaders::SelectedReposLoader.from_query(params[:filter], current_user)
    DashboardSurfaceController::DashboardSurfaceLayoutPayload.new(get_compact_mode_setting, get_saved_views, DashboardSurface::Payloads::SidebarLinks.links(current_user: current_user), global_sso_app_payload, selected_repos, { maxPrAge: current_user_max_pr_age }, get_pulls_default_view, get_collapsed_sections_setting, get_section_order_setting, get_hidden_sections_setting)
  end

  # Extracts only `repo:` qualifiers from the URL `filter` param, returning them as a
  # suffix string suitable for appending to a named section query (e.g. "review-requested").
  sig { returns(T.nilable(String)) }
  private def repo_scope_from_filter
    raw = params[:filter].to_s.strip
    return nil if raw.blank?

    parsed = ::Search::ParsedQuery.parse(raw, terms: [:repo], normalize_quotes: false)
    repo_values = T.let([], T::Array[String])
    parsed.each do |seg|
      next unless seg.is_a?(Array)

      key, value, negated = seg
      next unless key.to_sym == :repo
      next if negated

      v = value.to_s.strip
      repo_values << v unless v.blank?
    end

    repo_values.uniq!
    return nil if repo_values.empty?

    if repo_values.length == 1
      "repo:#{repo_values.first}"
    else
      repo_values.map { |v| "repo:#{v}" }.join(" ")
    end
  rescue StandardError
    nil
  end

  sig { returns(T::Boolean) }
  private def get_compact_mode_setting
    current_user ? current_user.settings.get(:dashboard_surface_compact_mode) : false
  rescue => e
    GitHub.logger.warn("Failed to load compact mode setting on Inbox: #{e.message}")
    GitHub.dogstats.increment("dashboard_surface.compact_mode_setting.failed", tags: ["inbox"])
    false
  end

  sig { returns(T::Array[String]) }
  private def get_collapsed_sections_setting
    DashboardSurface::Models::InboxSections.collapsed_section_ids_from_cookie(request.cookies["dashboard_surface_collapsed_sections"])
  end

  private

  # Returns the user's section order preference, or [] when the customize
  # feature is disabled. The frontend treats an empty array as "use default
  # order".
  sig { returns(T::Array[String]) }
  memoize def get_section_order_setting
    return [] unless customize_sections_enabled?

    DashboardSurface::Models::InboxSections.ordered_section_ids_from_cookie(
      request.cookies["dashboard_surface_section_order"],
    )
  end

  # Returns the set of sections the user has chosen to hide via the customize
  # dialog, or [] when the feature is disabled.
  sig { returns(T::Array[String]) }
  memoize def get_hidden_sections_setting
    return [] unless customize_sections_enabled?

    DashboardSurface::Models::InboxSections.hidden_section_ids_from_cookie(
      request.cookies["dashboard_surface_hidden_sections"],
    )
  end

  sig { returns(T::Boolean) }
  memoize def customize_sections_enabled?
    FeatureFlag.vexi.enabled?(:pull_request_inbox_customize_sections, current_user, default: false)
  end

  sig { returns(String) }
  private def current_user_max_pr_age
    DashboardSurface::Models::InboxSearchConfig.max_pr_age_for_user(current_user)
  end

  sig { returns(T::Hash[String, String]) }
  memoize def inbox_section_queries
    map = DashboardSurface::Models::InboxSections.query_map
    # Hidden sections are filtered before any loaders dispatch so they never
    # trigger ES queries.
    if customize_sections_enabled?
      hidden = get_hidden_sections_setting
      map = map.reject { |k, _| hidden.include?(k) } if hidden.any?
    end
    map
  end

  sig { returns(T::Array[DashboardSurface::Payloads::SavedView]) }
  private def get_saved_views
    DashboardSurface::Loaders::SavedViewLoader.load_for_user(
      current_user,
      DashboardSurface::Loaders::SavedViewLoader::SearchType::PullRequests,
    )
  rescue => e
    GitHub.logger.warn("Failed to load Inbox saved views: #{e.message}")
    GitHub.dogstats.increment("dashboard_surface.saved_views.failed", tags: ["inbox"])
    []
  end

  sig do
    params(query_config: DashboardSurface::Models::InboxSearchConfig)
      .returns([T::Array[Issue], Integer, T::Hash[Integer, String]])
  end
  private def find_issues(query_config)
    query_config.es_queries.each do |q|
      if q.include?("is:issue")
        GitHub.dogstats.increment("search.advanced_search.includes_is_issue")
        GitHub.dogstats.increment("dashboard_surface.search.includes_is_issue", tags: ["inbox"])
      end
    end
    issues, total_count, categories_by_issue_id = if unified_needs_action_query?(query_config)
      search_results = execute_search(
        phrase: query_config.es_query,
        page: query_config.page,
        per_page: query_config.maximum_result_limit,
        section: query_config.named_section || "custom"
      )

      [
        search_results.models,
        search_results.models.length,
        classify_unified_needs_action_issues(search_results),
      ]
    elsif query_config.composite?
      find_composite_issues(query_config)
    else
      search_results = execute_search(
        phrase: query_config.es_query,
        page: query_config.page,
        per_page: query_config.maximum_result_limit,
        section: query_config.named_section || "custom"
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

    section = query_config.named_section
    if section && MERGE_CONFLICT_OVERRIDE_SECTIONS.include?(section)
      override_merge_conflict_categories!(issues, categories_by_issue_id, section: section)
    end

    [issues, total_count, categories_by_issue_id]
  end

  sig do
    params(query_config: DashboardSurface::Models::InboxSearchConfig)
      .returns([T::Array[Issue], Integer, T::Hash[Integer, String]])
  end
  private def find_composite_issues(query_config)
    tags = ["composite:true"]
    result = T.cast(
      GitHub.dogstats.distribution_time("dashboard_surface.inbox.composite_search.duration_ms", tags: tags) do
        limit = query_config.maximum_result_limit

        es_queries = query_config.es_queries
        all_results = es_queries.map do |phrase|
          execute_search(
            phrase: phrase,
            page: query_config.page,
            per_page: limit,
            section: query_config.named_section || "custom"
          )
        end

        seen_ids = T.let(Set.new, T::Set[Integer])
        deduplicated_issues = T.let([], T::Array[Issue])
        categories_by_issue_id = T.let({}, T::Hash[Integer, String])

        all_results.each_with_index do |search_results, index|
          phrase = T.must(es_queries[index])
          category = category_for_named_query(phrase)

          search_results.results.each do |result|
            issue = result["_model"]
            next unless issue

            next if seen_ids.include?(issue.id)

            seen_ids.add(issue.id)
            deduplicated_issues << issue

            matched_queries = Array(result["matched_queries"])
            matched_category = matched_queries.empty? ? nil : category_for_unified_needs_action_matches(matched_queries)
            resolved_category = matched_category || category
            categories_by_issue_id[issue.id] = resolved_category if resolved_category
          end
        end

        deduplicated_issues = deduplicated_issues
          .sort_by { |issue| [issue.updated_at&.to_i || 0, issue.id] }
          .reverse
          .first(limit)

        total_count = deduplicated_issues.length

        [deduplicated_issues, total_count, categories_by_issue_id]
      end,
      [T::Array[Issue], Integer, T::Hash[Integer, String]],
    )

    result
  end

  # Relabels any surfaced issue whose PR has an a merge conflict, taking
  # precedence over its original section/sub-query category.
  sig do
    params(
      issues: T::Array[Issue],
      categories_by_issue_id: T::Hash[Integer, String],
      section: T.nilable(String),
    ).void
  end
  private def override_merge_conflict_categories!(issues, categories_by_issue_id, section:)
    section_tag = "section:#{section || "unknown"}"
    return if issues.empty?

    GitHub.dogstats.time("dashboard_surface.override_merge_conflict_categories.time", tags: [section_tag]) do
      pr_ids = issues.filter_map(&:pull_request_id)
      next if pr_ids.empty?

      conflicting_pr_ids = PullRequestConflict
        .where(pull_request_id: pr_ids, conflict_type: :merge_conflict)
        .pluck(:pull_request_id)
        .to_set
      next if conflicting_pr_ids.empty?

      issues.each do |issue|
        pr_id = issue.pull_request_id
        next unless pr_id && conflicting_pr_ids.include?(pr_id)

        categories_by_issue_id[issue.id] = "MERGE_CONFLICTS"
      end
    end
  rescue => e
    GitHub.dogstats.increment("dashboard_surface.override_merge_conflict_categories.failed", tags: [section_tag])
    GitHub.logger.warn("override_merge_conflict_categories! failed: #{e.message}")
  end

  sig { params(block: T.proc.void).void }
  private def measure_inbox_request(&block)
    GitHub.dogstats.time(
      "dashboard_surface.inbox_request.time",
      tags: ["action:#{action_name}"],
    ) { block.call }
  end

  sig { params(phrase: String).returns(T.nilable(String)) }
  private def category_for_named_query(phrase)
    candidates = [
      DashboardSurface::Queries::NEEDS_ACTION_CHANGES_REQUESTED_QUERY,
      DashboardSurface::Queries::NEEDS_ACTION_FAILING_CHECKS_QUERY,
      DashboardSurface::Queries::NEEDS_ACTION_AGENT_BLOCKED,
    ]

    normalized_phrase = candidates.find { |candidate| phrase == candidate || phrase.start_with?("#{candidate} ") }

    case normalized_phrase
    when DashboardSurface::Queries::NEEDS_ACTION_CHANGES_REQUESTED_QUERY, DashboardSurface::Queries::NEEDS_ACTION_AGENT_BLOCKED
      "CHANGES_REQUESTED"
    when DashboardSurface::Queries::NEEDS_ACTION_FAILING_CHECKS_QUERY
      "CI_FAILING"
    end
  end

  sig { params(search_results: Search::Results[T.untyped]).returns(T::Hash[Integer, String]) }
  private def classify_unified_needs_action_issues(search_results)
    search_results.results.each_with_object({}) do |result, categories|
      issue = result["_model"]
      next unless issue

      matched_queries = Array(result["matched_queries"])
      categories[issue.id] = category_for_unified_needs_action_matches(matched_queries) || "CHANGES_REQUESTED"
    end
  end

  sig { params(matched_queries: T::Array[T.untyped]).returns(T.nilable(String)) }
  private def category_for_unified_needs_action_matches(matched_queries)
    normalized_matches = matched_queries.map(&:to_s)

    return "CI_FAILING" if normalized_matches.include?("failing_checks")
    return "CHANGES_REQUESTED" if normalized_matches.include?("changes_requested")
    return "CHANGES_REQUESTED" if normalized_matches.include?("agent_blocked")

    if normalized_matches.any?
      GitHub.dogstats.increment("dashboard_surface.inbox.unified_needs_action.unrecognized_match")
      GitHub.logger.warn("unrecognized matched_queries for needs-action unified category: #{normalized_matches.join(",")}")
    end

    nil
  end

  sig { returns(T::Boolean) }
  private def needs_action_unified_query_enabled?
    FeatureFlag.vexi.enabled?(:dashboard_surface_needs_action_unified_query, current_user, default: false)
  end

  sig { params(query_config: DashboardSurface::Models::InboxSearchConfig).returns(T::Boolean) }
  private def unified_needs_action_query?(query_config)
    query_config.named_section == "needs-action" && needs_action_unified_query_enabled?
  end

  sig { params(section: T.nilable(String)).returns(T.nilable(String)) }
  private def category_for_named_section(section)
    case section
    when "needs-action"
      "CHANGES_REQUESTED"
    when "ready-to-merge"
      "READY_TO_MERGE"
    when "review-requested", "team-review-requested"
      "AWAITING_REVIEW"
    when "your-drafts"
      "YOUR_DRAFTS"
    when "waiting-for-review"
      "WAITING_FOR_REVIEW"
    when "merge-queue"
      "MERGE_QUEUE"
    end
  end

  sig { params(phrase: String, page: Integer, per_page: Integer, section: String).returns(Search::Results[T.untyped]) }
  private def execute_search(phrase:, page:, per_page:, section: "unknown")
    tags = [
      "section:#{section}",
      "composite:#{section == 'needs-action' ? 'true' : 'false'}"
    ]
    source_search = lambda do
      source_result = T.cast(
        GitHub.dogstats.distribution_time("dashboard_surface.inbox.search.duration_ms", tags: tags) do
          if section == "needs-action" && needs_action_unified_query_enabled?
            Search::Queries::InboxNeedsActionQuery.new(
              allow_insecure_user_to_server_app_query: false,
              current_user: current_user,
              user_session: user_session,
              remote_ip: request&.remote_ip,
              scope_phrase: phrase,
              page: page,
              per_page: per_page,
              source_fields: false,
              index: ::Elastomer::Indexes::Issues.by_type("pr"),
              context: "#{self.class.name&.demodulize&.underscore}-find_issues",
              routing_override: active_repo_routing_for(current_user),
            ).execute
          else
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
              routing_override: active_repo_routing_for(current_user),
            ).execute
          end
        end,
        Search::Results[T.untyped],
      )
      GitHub.dogstats.increment(
        "dashboard_surface.inbox.es_query.count",
        tags: tags
      )
      GitHub.dogstats.distribution(
        "dashboard_surface.inbox.es_query.result_count",
        source_result.models.length,
        tags: tags
      )

      source_result
    end

    unless FeatureFlag.vexi.enabled?(:dashboard_surface_inbox_search_remote_cache, current_user, default: false)
      return source_search.call
    end

    issue_ids_client = PullRequests::Cache::InboxSearchIssueIdsClient.new(
      current_user: current_user,
      phrase: phrase,
      page: page,
      per_page: per_page,
      section: section,
    )

    issue_ids = issue_ids_client.fetch do
      source_result = source_search.call

      source_result.models.map(&:id)
    end

    issues_by_id = if issue_ids.empty?
      {}
    else
      Issue.where(id: issue_ids).index_by(&:id)
    end

    issues = issue_ids.filter_map { |id| issues_by_id[id] }

    results = Search::Results.empty(total: issues.length)
    results.results = issues.map { |issue| { "_model" => issue } }
    results
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
    rescue => e
      GitHub.logger.warn("post_filter_ready_to_merge failed for issue #{issue.id}: #{e.message}")
      GitHub.dogstats.increment("dashboard_surface.post_filter_ready_to_merge.failed")
      false
    end
  end

  sig { returns(Symbol) }
  private def target_for_conditional_access
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  sig { returns(Symbol) }
  private def ip_allowlist_enforceable
    return :no if CAP_OPT_OUT_ACTIONS.include?(action_name)
    super
  end

  sig { returns(Symbol) }
  private def external_conditional_access_policy_enforceable
    return :no if CAP_OPT_OUT_ACTIONS.include?(action_name)
    super
  end

  sig { returns(Symbol) }
  private def two_factor_enforceable
    return :no if CAP_OPT_OUT_ACTIONS.include?(action_name)
    :yes
  end

  sig { returns(T::Boolean) }
  private def require_active_external_identity_session?
    return false if CAP_OPT_OUT_ACTIONS.include?(action_name)
    true
  end

  sig { params(issues: T::Array[Issue]).returns(T::Array[Issue]) }
  private def cap_filtered(issues)
    Array(cap_filter.authorized_resources(issues))
  end
end
