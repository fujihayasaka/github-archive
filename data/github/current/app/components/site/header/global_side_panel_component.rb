# typed: true
# frozen_string_literal: true

module Site
  module Header
    include HydroHelper

    class GlobalSidePanelComponent < SidePanelComponent
      include KeyboardShortcutsHelper
      include CopilotChatHelper
      include ResilienceHelper

      attr_reader :repositories, :teams, :items_per_page, :max_pages, :orgs_needing_sso

      def initialize(load_everything: false, rich_content_enabled: false, repositories: [], teams: [], items_per_page: nil, max_pages: nil, cookie_consent_enabled: false, orgs_needing_sso: [])
        super(load_everything: load_everything, rich_content_enabled: rich_content_enabled)
        @repositories = repositories
        @teams = teams
        @items_per_page = items_per_page
        @max_pages = max_pages
        @orgs_needing_sso = orgs_needing_sso
        @cookie_consent_enabled = cookie_consent_enabled
      end

      def panel_arguments
        {
          title: "Global navigation",
          position: :left,
          data: panel_data,
          test_selector: "global-side-panel-component",
          trigger_arguments: {
            icon: :"three-bars",
            scheme: :default,
            data: trigger_data,
            aria: {
              label: "Open global navigation menu",
            },
            classes: "AppHeader-button",
            color: :muted,
            show_tooltip: false,
            test_selector: "global-side-panel-trigger"
          }
        }
      end

      def group_data_args(src:, filter_item_type: nil)
        args = {
          group_arguments: {
            data: {
              src: src,
              items_per_page: items_per_page,
              max_pages: max_pages
            }
          }
        }
        args[:group_arguments][:data][:filter_item_type] = filter_item_type if filter_item_type
        args
      end

      def show_sso_banner?
        rich_content_enabled? && !placeholder? && orgs_needing_sso.any?
      end

      def show_marketplace_link?
        GitHub.marketplace_enabled?
      end

      def show_discussions_link?
        GitHub.discussions_available_on_platform?
      end

      def show_copilot_link?
        with_database_error_fallback(fallback: false) { logged_in? && copilot_chat_enabled_for_current_user? }
      end

      def hide_explore_link?
        GitHub.multi_tenant_enterprise?
      end

      def feedback_url
        "https://gh.io/navigation-update"
      end

      def dashboard_url
        dashboard_path
      end

      def explore_url
        explore_path
      end

      def marketplace_url
        marketplace_path
      end

      def all_issues_url
        all_issues_path
      end

      def all_pulls_url
        all_pulls_path
      end

      def projects_dashboard_url
        projects_dashboard_path
      end

      def all_discussions_url
        all_discussions_path
      end

      def about_url
        "#{static_public_url}#{about_path}"
      end

      def help_url
        GitHub.help_url
      end

      def blog_url
        GitHub.blog_url
      end

      def terms_url
        GitHub.terms_url
      end

      def privacy_url
        "#{help_url}/site-policy/privacy-policies/github-privacy-statement"
      end

      def show_security_link?
        !GitHub.enterprise?
      end

      def security_url
        "#{static_public_url}#{security_path}"
      end

      def status_url
        GitHub.status_url
      end

      def copilot_url
        copilot_immersive_path
      end

      def cookie_consent_enabled
        @cookie_consent_enabled
      end

      private

      def static_public_url
        "https://github.com"
      end
    end
  end
end
