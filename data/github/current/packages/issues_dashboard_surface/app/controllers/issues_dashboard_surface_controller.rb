# typed: strict
# frozen_string_literal: true

require "react_payload"

class IssuesDashboardSurfaceController < ApplicationController
  include DashboardHelper

  self.react_bundle_name = "dashboard-surface"

  before_action :login_required
  before_action :ensure_feature_enabled

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
    ApplicationRecord::Repositories,
    only: [:index, :content, :deferred]

  depends_on_clusters ApplicationRecord::NotificationsEntries,
    optional: true, only: [:index, :content, :deferred]

  global_navigation_title "Issues", only: [:index]

  class IssuesDashboardSurfaceLayoutPayload < ReactPayload::Base
    sig { override.returns(String) }
    def route_id
      "issuesDashboardSurfaceLayoutRoute"
    end

    sig { params(saved_views: T::Array[DashboardSurface::Payloads::SavedView], sso: T::Hash[Symbol, T.untyped], selected_repos: T::Array[Repository]).void }
    def initialize(saved_views, sso, selected_repos = [])
      @saved_views = saved_views
      @sso = sso
      @selected_repos = selected_repos
    end

    sig { override.returns(T::Hash[String, T.untyped]) }
    def payload
      DashboardSurface::Payloads::Layout.serialize(
        compact_mode: false,
        saved_views: @saved_views,
        sidebar_links: IssuesDashboardSurface::Payloads::SidebarLinks.links,
        sso: @sso,
        filters: {},
        selected_repos: @selected_repos,
        default_view_id: "assigned",
        collapsed_sections: [],
      )
    end
  end

  class IssuesDashboardSurfaceContentPayload < ReactPayload::Base
    sig { override.returns(String) }
    def route_id
      "issuesDashboardSurfaceContentRoute"
    end

    sig { params(results: T::Array[Issue], pagination: DashboardSurface::Pagination, error: T.nilable(String)).void }
    def initialize(results, pagination, error: nil)
      @results = results
      @pagination = pagination
      @error = error
    end

    sig { override.returns(T::Hash[String, T.untyped]) }
    def payload
      IssuesDashboardSurface::Payloads::SearchResults.serialize(
        results: @results,
        pagination: @pagination,
        error: @error,
      )
    end
  end

  class IssuesDashboardSurfaceDeferredPayload < ReactPayload::Base
    sig { override.returns(String) }
    def route_id
      "issuesDashboardSurfaceContentDeferredData"
    end

    sig { params(results: IssuesDashboardSurface::ResultsLoader::DeferredData).void }
    def initialize(results)
      @results = results
    end

    sig { override.returns(T::Hash[String, T.untyped]) }
    def payload
      IssuesDashboardSurface::Payloads::SearchResultsDeferredContent.serialize(@results)
    end
  end

  sig { void }
  def layout # rubocop:disable GitHub/UseRestfulActions
    respond_with_react(
      title: "Issues",
      payload: layout_payload,
    )
  end

  sig { void }
  def index
    # JSON requests from soft-navigations use the _content endpoint directly.
    # HTML page loads render content inline.
    search_results = find_results
    results = IssuesDashboardSurface::ResultsLoader.main_content_from(
      issues: cap_filtered(search_results.models),
      current_user:,
    )
    payload = IssuesDashboardSurfaceContentPayload.new(
      results,
      DashboardSurface::Pagination.new(
        current_page: search_results.current_page,
        total_pages: search_results.total_pages,
        total_count: search_results.total,
      ),
      error: search_results.error_message,
    )

    respond_with_react(
      payload: payload,
      title: "Issues",
      nested_payloads: -> { [layout_payload] },
      custom_tags: [
        "referrer_controller_action:issues#dashboard",
        "is_react:true",
      ],
      app_payload_generator: -> { global_sso_app_payload.merge(current_user: DashboardSurface::Payloads::CurrentUser.serialize(current_user)) }, # rubocop:todo GitHub/NoReactAppPayload
    )
  end

  sig { void }
  def content # rubocop:disable GitHub/UseRestfulActions
    search_results = find_results
    results = IssuesDashboardSurface::ResultsLoader.main_content_from(
      issues: cap_filtered(search_results.models),
      current_user:,
    )
    payload = IssuesDashboardSurfaceContentPayload.new(
      results,
      DashboardSurface::Pagination.new(
        current_page: search_results.current_page,
        total_pages: search_results.total_pages,
        total_count: search_results.total,
      ),
      error: search_results.error_message,
    )

    respond_with_react(
      payload: payload,
      title: "Issues",
      nested_payloads: -> { [layout_payload] },
      custom_tags: [
        "referrer_controller_action:issues#dashboard",
        "is_react:true",
      ],
      app_payload_generator: -> { global_sso_app_payload.merge(current_user: DashboardSurface::Payloads::CurrentUser.serialize(current_user)) }, # rubocop:todo GitHub/NoReactAppPayload
    )
  end

  sig { void }
  def deferred # rubocop:disable GitHub/UseRestfulActions
    search_results = find_results
    results_data = IssuesDashboardSurface::ResultsLoader.deferred_content_from(
      issues: cap_filtered(search_results.models),
      current_user:,
      include_reactions: reaction_sort?,
      cap_filter:,
    )
    payload = IssuesDashboardSurfaceDeferredPayload.new(results_data)

    respond_with_react(
      payload: payload,
      title: "Issues",
      nested_payloads: -> { [layout_payload] },
    )
  end

  sig { returns(T::Array[DashboardSurface::Payloads::SavedView]) }
  private def get_saved_views
    DashboardSurface::Loaders::SavedViewLoader.load_for_user(
      current_user,
      DashboardSurface::Loaders::SavedViewLoader::SearchType::Issues,
    )
  rescue => e
    GitHub.logger.warn("Failed to load issues dashboard saved views: #{e.message}")
    GitHub.dogstats.increment("issues_dashboard_surface.saved_views.failed")
    []
  end

  sig { returns(IssuesDashboardSurfaceLayoutPayload) }
  private def layout_payload
    selected_repos = DashboardSurface::Loaders::SelectedReposLoader.from_query(params[:filter], current_user)
    IssuesDashboardSurfaceLayoutPayload.new(
      get_saved_views,
      global_sso_app_payload,
      selected_repos,
    )
  end

  sig { returns(Search::Results[T.untyped]) }
  private def find_results
    query_config = IssuesDashboardSurface::SearchConfig.from_params(params, request.path, current_user: current_user)

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
      index: ::Elastomer::Indexes::Issues.by_type("issue"),
      context: "#{self.class.name&.demodulize&.underscore}-#{__method__}",
    )
    query.execute
  end

  REACTION_SORT_PATTERN = /\bsort:reactions(?:-\S+)?\b/

  sig { returns(T::Boolean) }
  private def reaction_sort?
    REACTION_SORT_PATTERN.match?(params[:q].to_s)
  end

  # Gate-level CAP enforcement is not applicable because this controller
  # is not scoped to a single organization. Results are filtered inline
  # via cap_filter.authorized_resources instead.
  CAP_OPT_OUT_ACTIONS = T.let(%w(index content deferred layout).freeze, T::Array[String])

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

  sig { void }
  private def ensure_feature_enabled
    return if FeatureFlag.vexi.enabled?("issues_dashboard_surface", current_user, default: false)

    head :not_found
  end
end
