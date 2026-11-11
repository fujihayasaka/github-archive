# typed: strict
# frozen_string_literal: true

require "react_payload"

class DashboardSurfaceController < ApplicationController
  include DashboardHelper

  before_action :login_required

  # This controller serves `/pulls` and is not consistently scoped to an organization.
  # needs investigation for protected organizations
  skip_before_action :perform_conditional_access_checks # rubocop:todo GitHub/DoNotSkipCapBeforeAction

  depends_on_clusters ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql1,
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
    only: [:deferred]

  class Pagination < T::Struct
    const :current_page, Integer
    const :total_pages, Integer
    const :total_count, Integer
  end

  class DashboardSurfaceLayoutPayload < ReactPayload::Base
    sig { override.returns(String) }
    def route_id
      "pullsDashboardSurfaceLayoutRoute"
    end

    sig { params(compact_mode: T::Boolean, saved_views: T::Array[DashboardSurface::Payloads::SavedView], sidebar_links: T::Array[DashboardSurface::Payloads::SidebarLinks::SidebarLink], sso: T::Hash[Symbol, T.untyped]).void }
    def initialize(compact_mode, saved_views, sidebar_links, sso)
      @compact_mode = compact_mode
      @saved_views = saved_views
      @sidebar_links = sidebar_links
      @sso = sso
    end

    sig { override.returns(T::Hash[String, T.untyped]) }
    def payload
      DashboardSurface::Payloads::Layout.serialize(compact_mode: @compact_mode, saved_views: @saved_views, sidebar_links: @sidebar_links, sso: @sso)
    end
  end

  class DashboardSurfaceRoutePayload < ReactPayload::Base
    sig { override.returns(String) }
    def route_id
      "pullsDashboardSurfaceContentRoute"
    end

    sig { params(results: T::Array[PullRequest], pagination: Pagination).void }
    def initialize(results, pagination)
      @results = results
      @pagination = pagination
    end

    sig { override.returns(T::Hash[String, T.untyped]) }
    def payload
      DashboardSurface::Payloads::SearchResults.serialize(
        @results,
        @pagination
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
    payload = DashboardSurfaceLayoutPayload.new(get_compact_mode_setting, get_saved_views, DashboardSurface::Payloads::SidebarLinks.links(current_user), global_sso_app_payload)

    respond_with_react(
      title: "Pull Requests",
      payload: payload,
    )
  end

  sig { void }
  def index
    if !dashboard_surface_react_app_enabled?
      GitHub.logger.info("Dashboard surface controller falling back to legacy controller for user #{current_user&.id}")
      return PullRequestsController.dispatch(:dashboard, request, response)
    end

    context_region_title "Pull Requests"

    search_results = find_results
    results = DashboardSurface::Loaders::ResultsLoader.main_content_from(
      issues: search_results.models,
      current_user:
    )
    payload = DashboardSurfaceRoutePayload.new(
      results,
      Pagination.new(
        current_page: search_results.current_page,
        total_pages: search_results.total_pages,
        total_count: search_results.total,
      )
    )
    layout_payload = DashboardSurfaceLayoutPayload.new(get_compact_mode_setting, get_saved_views, DashboardSurface::Payloads::SidebarLinks.links(current_user), global_sso_app_payload)

    respond_with_react(
      payload: payload,
      title: "Pull Requests",
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
    search_results = find_results
    results_data = DashboardSurface::Loaders::ResultsLoader.deferred_content_from(issues: search_results.models, current_user:)
    payload = DashboardSurfaceRouteDeferredPayload.new(results_data)
    layout_payload = DashboardSurfaceLayoutPayload.new(get_compact_mode_setting, get_saved_views, DashboardSurface::Payloads::SidebarLinks.links(current_user), global_sso_app_payload)

    respond_with_react(
      payload: payload,
      title: "Pull Requests",
      nested_payloads: -> { [layout_payload] },
    )
  end

  sig { returns(T::Boolean) }
  private def get_compact_mode_setting
    current_user ? current_user.settings.get(:dashboard_surface_compact_mode) : false
  end

  sig { returns(T::Array[DashboardSurface::Payloads::SavedView]) }
  private def get_saved_views
    DashboardSurface::Loaders::SavedViewLoader.load_for_user(
      current_user,
      DashboardSurface::Loaders::SavedViewLoader::SearchType::PullRequests
    )
  end

  sig { returns(Search::Results[T.untyped]) }
  private def find_results
    query_config = DashboardSurface::Models::SearchConfig.from_params(params)

    if query_config.es_query.include?("is:issue")
      GitHub.dogstats.increment("search.advanced_search.includes_is_issue")
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
end
