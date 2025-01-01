# typed: true
# frozen_string_literal: true

module Site
  class HeaderComponent < ApplicationComponent
    include CommandPaletteHelper
    include KeyboardShortcutsHelper
    include ResilienceHelper
    include Mobile::ApplicationHelper
    include Search::Blackbird::Features

    sig { returns(T.nilable(ContextRegion::Crumb)) }
    attr_reader :context_crumb

    attr_reader :home_url, :user_can_create_organizations, :current_repository, :memex_enabled, :feature_preview_enabled, :eager_load_global_nav, :react_global_create_menu, :show_navigation_component

    sig do
      params(
        home_url: String,
        user_can_create_organizations: T::Boolean,
        current_repository: T.nilable(Repository),
        memex_enabled: T::Boolean,
        feature_preview_enabled: T::Boolean,
        context_crumb: T.nilable(ContextRegion::Crumb),
        rich_content_enabled: T.nilable(T::Boolean),
        eager_load_global_nav: T.nilable(T::Boolean),
        react_global_create_menu: T.nilable(T::Boolean),
        cookie_consent_enabled: T.nilable(T::Boolean),
        account_switcher_helper: T.nilable(AccountSwitcher::Helper),
        show_navigation_component: T.nilable(T::Boolean),
      ).void
    end
    def initialize(home_url:, user_can_create_organizations:, current_repository:, memex_enabled:, feature_preview_enabled:, context_crumb: nil, rich_content_enabled: false, eager_load_global_nav: false, react_global_create_menu: false, cookie_consent_enabled: false, account_switcher_helper: nil, show_navigation_component: true)
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
      @show_navigation_component = show_navigation_component
    end

    def rich_content_enabled?
      !!@rich_content_enabled
    end

    def context_items
      context_crumb&.crumbs || []
    end

    memoize def navigation_component
      return nil unless show_navigation_component
      context_crumb&.header_navigation_component
    end

    memoize def navigation_popover_component
      return nil unless show_navigation_component
      context_crumb&.header_navigation_popover_component
    end

    def user_or_global_preview_enabled?(preview_name)
      helpers.user_or_global_preview_enabled?(preview_name)
    end

    memoize def tracking_tags
      ["context_region_type:#{context_crumb.class.name&.underscore}"]
    end

    memoize def hide_menu_and_logo_on_desktop?
      global_nav_experiment_enabled?
    end

    def cookie_consent_enabled
      @cookie_consent_enabled
    end

    def global_nav_experiment_enabled?
      current_user.feature_preview_enabled?(:global_nav_experiment)
    end

    memoize def repos_contributed_page_enabled?
      !GitHub.enterprise? && FeatureFlag.vexi.enabled?(:repos_relevance_page, current_user, default: false)
    end
  end
end
