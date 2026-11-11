# typed: strict
# frozen_string_literal: true

module GlobalNavigation
  class NavMenuPayload < BasePayload
    include DashboardHelper

    sig { override.returns(String) }
    def route_id
      "navMenuRoute"
    end

    sig { override.returns(T::Hash[T.untyped, T.untyped]) }
    def payload
      GitHub.dogstats.time("global_navigation.nav_menu", tags: tracking_tags) do
        {
          home: {
            href: dashboard_path
          },
          feed: {
            show: show_feed_link?,
            href: feed_path
          },
          issues: issues_payload,
          pulls: pulls_payload,
          contributedRepos: contributed_repos_payload,
          projects: {
            href: projects_dashboard_path
          },
          discussions: {
            show: show_discussions_link?,
            href: show_discussions_link? ? all_discussions_path : nil
          },
          codespaces: {
            show: GitHub.codespaces_enabled?,
            href: codespaces_path
          },
          copilot: {
            show: show_copilot_link?,
            href: show_copilot_link? ? copilot_immersive_path : nil
          },
          spark: {
            show: show_copilot_link? && show_spark_link?,
            href: show_copilot_link? && show_spark_link? ? spark_dashboard_path : nil
          },
          marketplace: {
            show: GitHub.marketplace_enabled?,
            href: GitHub.marketplace_enabled? ? marketplace_path : nil
          },
          mcp: {
            show: GitHub.mcp_registry_enabled?,
            href: GitHub.mcp_registry_enabled? ? mcp_registry_path : nil
          },
          explore: {
            show: GitHub.explore_enabled?,
            href: GitHub.explore_enabled? ? explore_path : nil
          },
          richContent: {
            show: true,
            contentUrl: side_panels_path(panel: :global, format: :json),
            repositoriesSearchUrl: side_panel_items_path(panel: :global, type: :repositories, format: :json),
          },
        }
      end
    end

    sig { returns(T::Boolean) }
    memoize def show_feed_link?
      with_database_error_fallback(fallback: false) { logged_in? && dashboard_universe_enabled? }
    end

    sig { returns(T::Boolean) }
    memoize def show_discussions_link?
      GitHub.discussions_available_on_platform?
    end

    sig { returns(T::Boolean) }
    memoize def show_copilot_link?
      logged_in? && copilot_enabled?
    end

    sig { returns(T::Boolean) }
    memoize def show_spark_link?
      logged_in? && spark_enabled?
    end
  end
end
