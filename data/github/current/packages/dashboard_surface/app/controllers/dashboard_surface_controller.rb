# typed: strict
# frozen_string_literal: true

require "react_payload"

class DashboardSurfaceController < ApplicationController
  include DashboardHelper
  include Pulls::OpenStateClosedByPrefillExclusion

  before_action :login_required

  # Gate-level CAP enforcement is not applicable because this controller
  # is not scoped to a single organization. Results are filtered inline
  # via cap_filter.authorized_resources instead.
  CAP_OPT_OUT_ACTIONS = T.let(%w(index layout deferred).freeze, T::Array[String])

  depends_on_clusters ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    only: [:layout]

  depends_on_clusters ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Pages,
    ApplicationRecord::Repositories,
    only: [:index]

  depends_on_clusters ApplicationRecord::NotificationsEntries,
    optional: true, only: [:index]

  depends_on_clusters ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::RepositoriesActionsChecks,
    only: [:deferred]

  global_navigation_title "Pull requests", only: [:index]

  Pagination = DashboardSurface::Pagination

  class DashboardSurfaceLayoutPayload < ReactPayload::Base
    sig { override.returns(String) }
    def route_id
      "pullsDashboardSurfaceLayoutRoute"
    end

    sig { params(compact_mode: T::Boolean, saved_views: T::Array[DashboardSurface::Payloads::SavedView], sidebar_links: T::Array[DashboardSurface::Payloads::SidebarLinks::SidebarLink], sso: T::Hash[Symbol, T.untyped], selected_repos: T::Array[Repository], filters: T::Hash[Symbol, T.untyped], default_view_id: String, collapsed_sections: T::Array[String], section_order: T::Array[String], hidden_sections: T::Array[String]).void }
    def initialize(compact_mode, saved_views, sidebar_links, sso, selected_repos = [], filters = {}, default_view_id = DashboardHelper::DEFAULT_PULLS_DEFAULT_VIEW, collapsed_sections = [], section_order = [], hidden_sections = [])
      @compact_mode = compact_mode
      @saved_views = saved_views
      @sidebar_links = sidebar_links
      @sso = sso
      @filters = filters
      @selected_repos = selected_repos
      @collapsed_sections = collapsed_sections
      @default_view_id = default_view_id
      @section_order = section_order
      @hidden_sections = hidden_sections
    end

    sig { override.returns(T::Hash[String, T.untyped]) }
    def payload
      DashboardSurface::Payloads::Layout.serialize(compact_mode: @compact_mode, saved_views: @saved_views, sidebar_links: @sidebar_links, sso: @sso, filters: @filters, selected_repos: @selected_repos, default_view_id: @default_view_id, collapsed_sections: @collapsed_sections, section_order: @section_order, hidden_sections: @hidden_sections)
    end
  end

  class DashboardSurfaceRoutePayload < ReactPayload::Base
    sig { override.returns(String) }
    def route_id
      "pullsDashboardSurfaceContentRoute"
    end

    sig { params(results: T::Array[PullRequest], pagination: Pagination, error: T.nilable(String), viewer: T.nilable(User)).void }
    def initialize(results, pagination, error: nil, viewer: nil)
      @results = results
      @pagination = pagination
      @error = error
      @viewer = viewer
    end

    sig { override.returns(T::Hash[String, T.untyped]) }
    def payload
      DashboardSurface::Payloads::SearchResults.serialize(
        results: @results,
        pagination: @pagination,
        error: @error,
        viewer: @viewer,
      )
    end
  end

  class DashboardSurfaceRouteDeferredPayload < ReactPayload::Base
    sig { override.returns(String) }
    def route_id
      "pullsDashboardSurfaceContentDeferredData"
    end

    sig { params(results: DashboardSurface::Loaders::ResultsLoader::DeferredData).void }
    def initialize(results)
      @results = results
    end

    sig { override.returns(T::Hash[String, T.untyped]) }
    def payload
      DashboardSurface::Payloads::SearchResultsDeferredContent.serialize(@results)
    end
  end

  sig { void }
  def layout # rubocop:disable GitHub/UseRestfulActions
    respond_with_react(
      title: "Pull requests",
      payload: layout_payload,
    )
  end

  sig { void }
  def index
    if !dashboard_surface_react_app_enabled?
      GitHub.logger.info("Dashboard surface controller falling back to legacy controller for user #{current_user&.id}")
      GitHub.dogstats.increment("dashboard_surface.legacy_fallback")
      return PullRequestsController.dispatch(:dashboard, request, response)
    end

    # Dispatch page loads to the inbox controller. Only JSON requests from
    # /pulls/:mode soft-navigations need pullsDashboardSurfaceContentRoute.
    # We check for JSON rather than HTML because browsers like Firefox may
    # send Accept: */* for prefetch/prerender requests, causing
    # request.format.html? to return false even for page navigations.
    unless request.format.json? || known_pulls_path?
      default_view = get_pulls_default_view
      if default_view != DashboardHelper::DEFAULT_PULLS_DEFAULT_VIEW && request.path == "/pulls"
        return redirect_to "/pulls/#{default_view}"
      end

      return DashboardSurfaceInboxController.dispatch(:index, request, response)
    end

    begin
       query_config = DashboardSurface::Models::SearchConfig.from_params(params, request.path, current_user: current_user)
       search_results = find_results(query_config)
       exclude_prefills = T.let([], T::Array[Symbol])
       if exclude_closed_by_prefill_for_open_state_query?(query_config.es_query)
         exclude_prefills = [:closed_by]
       end
       results = DashboardSurface::Loaders::ResultsLoader.main_content_from(
         issues: cap_filtered(search_results.models),
         current_user:,
         exclude_prefills: exclude_prefills,
       )
       payload = DashboardSurfaceRoutePayload.new(
         results,
         Pagination.new(
           current_page: search_results.current_page,
           total_pages: search_results.total_pages,
           total_count: search_results.total,
         ),
         error: search_results.error_message,
         viewer: current_user,
       )
     rescue ElastomerClient::Client::Error, Faraday::Error => e
       GitHub.logger.warn("DashboardSurfaceController#index: search failed: #{e.message}")
       GitHub.dogstats.increment("dashboard_surface.index.search_failed", tags: ["surface"])
       Failbot.report(e)

       payload = DashboardSurfaceRoutePayload.new(
         [],
         Pagination.new(current_page: 1, total_pages: 0, total_count: 0),
         error: "search_service_unavailable",
         viewer: current_user,
       )
     end

    respond_with_react(
      payload: payload,
      title: "Pull requests",
      nested_payloads: -> { [layout_payload] },
      custom_tags: [
        "referrer_controller_action:pull_requests#dashboard",
        "is_react:true"
      ],
      app_payload_generator: -> { global_sso_app_payload.merge(current_user: DashboardSurface::Payloads::CurrentUser.serialize(current_user)) },
    )
  end

  sig { void }
  def deferred # rubocop:disable GitHub/UseRestfulActions
    results_data = begin
      issues = if params[:pr_ids].present?
        load_authorized_issues_from_pr_ids(Array(params[:pr_ids]).map(&:to_i))
      else
        query_config = DashboardSurface::Models::SearchConfig.from_params(params, request.path, current_user: current_user)
        find_results(query_config).models
      end
      DashboardSurface::Loaders::ResultsLoader.deferred_content_from(issues: cap_filtered(issues), current_user:)
    rescue => e
      GitHub.logger.warn("Failed to load deferred content: #{e.message}")
      GitHub.dogstats.increment("dashboard_surface.deferred_content.failed", tags: ["surface"])
      DashboardSurface::Loaders::ResultsLoader::DeferredData.empty
    end
    payload = DashboardSurfaceRouteDeferredPayload.new(results_data)
    respond_with_react(
      payload: payload,
      title: "Pull requests",
      nested_payloads: -> { [layout_payload] },
    )
  end

  sig { returns(T::Boolean) }
  private def get_compact_mode_setting
    current_user ? current_user.settings.get(:dashboard_surface_compact_mode) : false
  rescue => e
    GitHub.logger.warn("Failed to load compact mode setting: #{e.message}")
    GitHub.dogstats.increment("dashboard_surface.compact_mode_setting.failed", tags: ["surface"])
    false
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  private def get_inbox_filters
    { maxPrAge: DashboardSurface::Models::InboxSearchConfig.max_pr_age_for_user(current_user) }
  end

  sig { returns(T::Array[DashboardSurface::Payloads::SavedView]) }
  private def get_saved_views
    DashboardSurface::Loaders::SavedViewLoader.load_for_user(
      current_user,
      DashboardSurface::Loaders::SavedViewLoader::SearchType::PullRequests
    )
  rescue => e
    GitHub.logger.warn("Failed to load saved views: #{e.message}")
    GitHub.dogstats.increment("dashboard_surface.saved_views.failed", tags: ["surface"])
    []
  end

  sig { returns(DashboardSurfaceLayoutPayload) }
  private def layout_payload
    selected_repos = DashboardSurface::Loaders::SelectedReposLoader.from_query(params[:filter], current_user)

    DashboardSurfaceLayoutPayload.new(
      get_compact_mode_setting,
      get_saved_views,
      DashboardSurface::Payloads::SidebarLinks.links(current_user: current_user),
      global_sso_app_payload,
      selected_repos,
      get_inbox_filters,
      get_pulls_default_view,
      get_collapsed_sections_setting
    )
  end

  sig { returns(T::Array[String]) }
  private def get_collapsed_sections_setting
    DashboardSurface::Models::InboxSections.collapsed_section_ids_from_cookie(request.cookies["dashboard_surface_collapsed_sections"])
  end

  sig { returns(T::Boolean) }
  private def known_pulls_path?
    known_paths = [
      all_pulls_authored_path,
      all_pulls_assigned_path,
      all_pulls_involves_path,
      all_pulls_mentioned_path,
      all_pulls_reviews_path,
      all_pulls_review_requested_path,
      all_pulls_search_path,
    ]
    known_paths.include?(request.path) || request.path_parameters[:saved_view_id].present?
  end

  sig { params(query_config: DashboardSurface::Models::SearchConfig).returns(Search::Results[T.untyped]) }
  private def find_results(query_config)
    if query_config.es_query.include?("is:issue")
      GitHub.dogstats.increment("search.advanced_search.includes_is_issue")
      GitHub.dogstats.increment("dashboard_surface.search.includes_is_issue", tags: ["surface"])
    end

    query = Search::Queries::ConditionalIssueQuery.new(
      allow_insecure_user_to_server_app_query: false,
      current_user: current_user,
      user_session: user_session,
      remote_ip: request&.remote_ip,
      phrase: query_config.es_query,
      page: query_config.page,
      per_page: query_config.maximum_result_limit,
      source_fields: false,
      ngram_title: true,
      index: ::Elastomer::Indexes::Issues.by_type("pr"),
      context: "#{self.class.name&.demodulize.underscore}-#{__method__}",
    )
    query.execute
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
