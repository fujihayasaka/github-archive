# typed: true
# frozen_string_literal: true

module Site
  class HeaderComponent < ApplicationComponent
    include CommandPaletteHelper
    include KeyboardShortcutsHelper
    include ResilienceHelper
    include Mobile::ApplicationHelper
    attr_reader :home_url, :user_can_create_organizations, :current_repository, :memex_enabled, :feature_preview_enabled, :context_crumb, :eager_load_global_nav, :react_global_create_menu

    def initialize(home_url:, user_can_create_organizations:, current_repository:, memex_enabled:, feature_preview_enabled:, context_crumb: nil, rich_content_enabled: false, eager_load_global_nav: false, react_global_create_menu: false, cookie_consent_enabled: false, account_switcher_helper: nil)
      @home_url = home_url
      @user_can_create_organizations = user_can_create_organizations
      @current_repository = current_repository
      @memex_enabled = memex_enabled
      @feature_preview_enabled = feature_preview_enabled
      @context_crumb = context_crumb
      @rich_content_enabled = rich_content_enabled
      @eager_load_global_nav = eager_load_global_nav
      @react_global_create_menu = react_global_create_menu
      @cookie_consent_enabled = cookie_consent_enabled
      @account_switcher_helper = account_switcher_helper
    end

    def rich_content_enabled?
      !!@rich_content_enabled
    end

    def context_items
      context_crumb&.crumbs || []
    end

    memoize def navigation_component
      context_crumb&.header_navigation_component
    end

    def user_or_global_preview_enabled?(preview_name)
      helpers.user_or_global_preview_enabled?(preview_name)
    end

    memoize def tracking_tags
      ["context_region_type:#{context_crumb.class.name.underscore}"]
    end

    memoize def blackbird_enabled?
      (logged_in? || GitHub.flipper[:anonymous_search_and_codeview].enabled?) && GitHub.flipper[:react_code_search_enabled].enabled?
    end

    def cookie_consent_enabled
      @cookie_consent_enabled
    end
  end
end
