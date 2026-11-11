# typed: strict
# frozen_string_literal: true

module Site
  class HeaderComponent < ApplicationComponent
    include KeyboardShortcutsHelper
    include ResilienceHelper
    include SiteHelper
    include Mobile::ApplicationHelper
    include Search::Blackbird::Features
    include InProductTargeting::TransactionalMessageConcern

    sig { returns(T.nilable(ContextRegion::Crumb)) }
    attr_reader :context_crumb

    sig { returns(String) }
    attr_reader :home_url

    sig { returns(T::Boolean) }
    attr_reader :user_can_create_organizations

    sig { returns(T::Boolean) }
    attr_reader :memex_enabled

    sig { returns(T.nilable(T.any(Symbol, String))) }
    attr_reader :selected_link

    sig { returns(T::Boolean) }
    attr_reader :feature_preview_enabled

    sig { returns(T.nilable(T::Boolean)) }
    attr_reader :show_navigation_component

    sig { returns(T.nilable(AccountSwitcher::Helper)) }
    attr_reader :account_switcher_helper

    sig { returns(T.nilable(Object)) }
    attr_reader :page_breadcrumb_object

    sig do
      params(
        home_url: String,
        user_can_create_organizations: T::Boolean,
        current_repository: T.nilable(Repository),
        memex_enabled: T::Boolean,
        feature_preview_enabled: T::Boolean,
        context_crumb: T.nilable(ContextRegion::Crumb),
        selected_link: T.nilable(T.any(Symbol, String)),
        rich_content_enabled: T.nilable(T::Boolean),
        cookie_consent_enabled: T.nilable(T::Boolean),
        account_switcher_helper: T.nilable(AccountSwitcher::Helper),
        show_navigation_component: T.nilable(T::Boolean),
        page_breadcrumb_object: T.nilable(Object),
      ).void
    end
    def initialize(home_url:, user_can_create_organizations:, current_repository:, memex_enabled:, feature_preview_enabled:, context_crumb: nil, selected_link: nil, rich_content_enabled: false, cookie_consent_enabled: false, account_switcher_helper: nil, show_navigation_component: true, page_breadcrumb_object: nil)
      @home_url = home_url
      @user_can_create_organizations = user_can_create_organizations
      @current_repository = current_repository
      @memex_enabled = memex_enabled
      @feature_preview_enabled = feature_preview_enabled
      @context_crumb = context_crumb
      @selected_link = selected_link
      @rich_content_enabled = rich_content_enabled
      @cookie_consent_enabled = cookie_consent_enabled
      @account_switcher_helper = account_switcher_helper
      @show_navigation_component = show_navigation_component
      @page_breadcrumb_object = page_breadcrumb_object
    end

    sig { returns(T::Boolean) }
    def rich_content_enabled?
      !!@rich_content_enabled
    end

    sig { returns(T::Array[T.untyped]) }
    def context_items
      context_crumb&.crumbs || []
    end

    sig { returns(Site::HeaderView) }
    memoize def view
      Site::HeaderView.new(
        current_user: current_user,
        current_repository: current_repository,
        current_organization: current_organization,
        is_mobile_request: mobile?,
        current_copilot_user: current_copilot_user_v2,
        params: params,
        response: response,
      )
    end

    sig { overridable.returns(T.nilable(T.any(Site::Header::UnderlineNavComponent, Repositories::UnderlineNavComponent))) }
    memoize def navigation_component
      return nil unless show_navigation_component
      context_crumb&.header_navigation_component
    end

    sig { returns(T.nilable(Primer::Component)) }
    memoize def navigation_popover_component
      return nil unless show_navigation_component
      context_crumb&.header_navigation_popover_component
    end

    sig { params(preview_name: Symbol).returns(T::Boolean) }
    def user_or_global_preview_enabled?(preview_name)
      helpers.user_or_global_preview_enabled?(preview_name)
    end

    sig { returns(T::Array[String]) }
    memoize def tracking_tags
      projects_count_excluded = FeatureFlag.vexi.enabled?(:global_nav_exclude_project_count, current_repository, default: false)
      security_count_cache_enabled = FeatureFlag.vexi.enabled?(:global_nav_security_count_cache, current_repository, default: false)

      [
        "context_region_type:#{context_crumb&.crumb_type}",
        "projects_count_excluded:#{projects_count_excluded}",
        "security_count_cache_enabled:#{security_count_cache_enabled}",
      ]
    end

    sig { returns(T.nilable(T::Boolean)) }
    def cookie_consent_enabled
      @cookie_consent_enabled
    end

    sig { returns(T.nilable(T::Boolean)) }
    memoize def repos_contributed_page_enabled?
      !GitHub.enterprise? && FeatureFlag.vexi.enabled?(:repos_relevance_page, current_user, default: false)
    end

    sig { returns(T::Boolean) }
    def global_nav_react_enabled?
      FeatureFlag.vexi.enabled?(:global_nav_react, current_user, default: false)
    end

    sig { returns(T::Hash[T.untyped, T.untyped]) }
    def global_nav_react_props
      GitHub.dogstats.time("global_navigation.react_props", tags: tracking_tags) do
        global_nav_payload.payload(
          return_to: return_to_path,
          context_crumb: context_crumb,
          path_resolver: path_resolver,
          params: params,
          display_switch_account_popover: display_switch_account_popover?
        )
      end
    end

    sig { returns(Proc) }
    def path_resolver
      lambda do |path_method, args|
        helpers.send(path_method, *args) # rubocop:disable GitHub/AvoidObjectSendWithDynamicMethod
      end
    end

    sig { returns(T::Hash[T.untyped, T.untyped]) }
    def nav_menu_props
      GlobalNavigation::NavMenuPayload.new(
        current_user: current_user,
        current_copilot_user: current_copilot_user_v2,
        source: "react_partial"
      ).payload
    end

    sig { returns(GlobalNavigation::GlobalNavigationPayload) }
    memoize def global_nav_payload
      GlobalNavigation::GlobalNavigationPayload.new(
        current_user: current_user,
        current_copilot_user: current_copilot_user_v2,
        current_repository: current_repository,
        current_organization: current_organization,
        selected_link: selected_link,
        page_breadcrumb_object: page_breadcrumb_object,
        is_search_page: is_search_page? || false,
        view: view,
        source: "rails"
      )
    end

    sig { returns(T.nilable(Repository)) }
    def current_repository
      @current_repository
    end

    sig { returns(T.nilable(T::Boolean)) }
    memoize def is_search_page?
      if blackbird_enabled?
        current_page?(search_path) || (current_repository.present? && current_page?(repo_search_path(T.must(current_repository).owner, current_repository)))
      else
        current_page?(view.unscoped_search_path) || (GitHub.enterprise? && current_page?(view.unscoped_dotcom_search_path)) || (view.scoped_search_path && current_page?(view.scoped_search_path))
      end
    end
  end
end
