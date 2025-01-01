# typed: true
# frozen_string_literal: true

module Site
  module Header
    include HydroHelper
    include UrlHelper

    class GlobalSidePanelExperimentComponent < GlobalSidePanelComponent

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
          show_header: false,
          trigger_arguments: {
            is_experimental: true,
            text: "More",
            classes: "GlobalSidebar-button",
            data: trigger_data,
            text_icon: :"kebab-horizontal",
            scheme: :invisible,
            size: :small
          }
        }
      end

      private

      def current_page?(path)
        current_path = T.must(request).path || ""
        # Remove query parameters and trailing slashes for comparison
        current_path.sub(/\?.*/, "").chomp("/") == path.sub(/\?.*/, "").chomp("/")
      end
    end
  end
end
