# typed: true
# frozen_string_literal: true

module Site
  class HeaderComponent < ApplicationComponent
    include CommandPaletteHelper
    include KeyboardShortcutsHelper
    include ResilienceHelper
    include GistsHelper
    include UsersHelper
    include SiteHelper
    include Mobile::ApplicationHelper
    include Search::Blackbird::Features

    sig { returns(T.nilable(ContextRegion::Crumb)) }
    attr_reader :context_crumb

    attr_reader :home_url, :user_can_create_organizations, :current_repository, :memex_enabled, :feature_preview_enabled, :eager_load_global_nav, :react_global_create_menu, :show_navigation_component, :account_switcher_helper

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
        eager_load_global_nav: T.nilable(T::Boolean),
        react_global_create_menu: T.nilable(T::Boolean),
        cookie_consent_enabled: T.nilable(T::Boolean),
        account_switcher_helper: T.nilable(AccountSwitcher::Helper),
        show_navigation_component: T.nilable(T::Boolean),
      ).void
    end
    def initialize(home_url:, user_can_create_organizations:, current_repository:, memex_enabled:, feature_preview_enabled:, context_crumb: nil, selected_link: nil, rich_content_enabled: false, eager_load_global_nav: false, react_global_create_menu: false, cookie_consent_enabled: false, account_switcher_helper: nil, show_navigation_component: true)
      @home_url = home_url
      @user_can_create_organizations = user_can_create_organizations
      @current_repository = current_repository
      @memex_enabled = memex_enabled
      @feature_preview_enabled = feature_preview_enabled
      @context_crumb = context_crumb
      @selected_link = selected_link
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
      logged_in? && current_user.feature_preview_enabled?(:global_nav_experiment)
    end

    memoize def repos_contributed_page_enabled?
      !GitHub.enterprise? && FeatureFlag.vexi.enabled?(:repos_relevance_page, current_user, default: false)
    end

    def global_nav_react_enabled?
      FeatureFlag.vexi.enabled?(:global_nav_react, current_user, default: false)
    end

    def show_discussions_link?
      GitHub.discussions_available_on_platform?
    end

    def show_copilot_link?
      with_database_error_fallback(fallback: false) { logged_in? && helpers.show_copilot_chat_entrypoint? }
    end

    def show_spark_link?
      with_database_error_fallback(fallback: false) { logged_in? && helpers.show_spark_entrypoint? }
    end

    def show_feed_link?
      with_database_error_fallback(fallback: false) { logged_in? && helpers.dashboard_universe_enabled? }
    end

    def user
      @user || current_user
    end

    def create_menu_props
      Site::Header::AddDropdownComponentProps.new(
        current_user: current_user,
        current_organization: current_organization,
        user_can_create_organizations: user_can_create_organizations,
        repository: current_repository,
        memex_enabled: memex_enabled,
        show_issue_create_link: user_feature_enabled?(:issues_react_global_add),
      ).create_menu_props
    end

    def show_your_organizations_link?
      return false if user&.is_enterprise_managed? && user&.enterprise_managed_business&.seats_plan_basic?
      true
    end

    def context_region_payload
      return {} unless context_crumb

      # Dynamic method needed in order to resolve Rails path helper methods for crumbs and Repository tabs
      path_resolver = lambda do |path_method, args|
        helpers.send(path_method, *args) # rubocop:disable GitHub/AvoidObjectSendWithDynamicMethod
      end

      ContextRegion::ReactPayload.generate(
        crumb: context_crumb,
        path_resolver: path_resolver,
        current_user: current_user,
        selected_link: @selected_link,
      )
    end

    def account_switch_dialog_props
      return { show: false } unless account_switcher_helper && display_switch_account_popover?

      {
        show: true,
        stashedAccounts: account_switcher_helper.stashed_accounts.valid.map do |account|
          {
            login: account.user.display_login,
            name: account.user.profile_name,
            avatarUrl: account.user.primary_avatar_url,
            userSessionId: account.user_session&.id,
          }
        end
      }
    end

    def global_nav_react_props
      {
        contextRegion: context_region_payload,
        navMenu:  {
          home: {
            href: dashboard_url,
            hotkey: hotkeys_for(current_user, :global, :go_to_dashboard)
          },
          feed: {
            show: show_feed_link?,
            href: feed_url
          },
          issues: {
            href: all_issues_url,
            hotkey: hotkeys_for(current_user, :global, :go_to_your_issues)
          },
          pulls: {
            href: all_pulls_url,
            hotkey: hotkeys_for(current_user, :global, :go_to_your_pull_requests)
          },
          contributedRepos: {
            show: repos_contributed_page_enabled?,
            href: repos_contributed_page_enabled? ? repositories_finder_url : nil, # that route helper is not available in Enterprise mode
            hotkey: hotkeys_for(current_user, :global, :go_to_your_contributed_repos)
          },
          projects: {
            href: projects_dashboard_url
          },
          discussions: {
            show: show_discussions_link?,
            href: show_discussions_link? ? all_discussions_url : nil
          },
          codespaces: {
            show: GitHub.codespaces_enabled?,
            href: codespaces_url
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
            href: GitHub.marketplace_enabled? ? marketplace_url : nil
          },
          explore: {
            show: GitHub.explore_enabled?,
            href: GitHub.explore_enabled? ? explore_url : nil
          },
          richContent: {
            show: rich_content_enabled?,
            contentUrl: side_panels_path(panel: :global, format: :json),
            repositoriesSearchUrl: side_panel_items_path(panel: :global, type: :repositories, format: :json),
            teamsSearchUrl: side_panel_items_path(panel: :global, type: :teams, format: :json),
          },
        },
        accountSwitchDialog: account_switch_dialog_props,
        userMenu: {
          owner: {
            login: current_user.display_login,
            name: current_user.profile_name,
            avatarUrl: current_user.primary_avatar_url
          },
          drawerId: "global-user-nav-drawer",
          lazyLoadItemDataFetchUrl: side_panels_path(panel: :user, format: :json),
          canAddAccount: @account_switcher_helper&.can_add_account? || false,
          addAccountPath: add_account_path,
          switchAccountPath: switch_account_path,
          loginAccountPath: login_path(add_account: 1),
          projectsPath: user_path(user, params: { tab: "projects" }),
          gistsUrl: my_gists_url,
          docsUrl: GitHub.help_url,
          yourEnterpriseUrl:  show_your_enterprise_user_menu? ? enterprise_url(your_enterprise_user_menu_slug) : nil,
          enterpriseSettingsUrl: GitHub.single_business_environment? ? enterprise_url(GitHub.global_business.slug) : nil,
          supportUrl: GitHub.support_url,
          showAccountSwitcher: @account_switcher_helper ? @account_switcher_helper.enabled? : false,
          showCopilot: !GitHub.enterprise? && !GitHub.multi_tenant_enterprise?,
          showEnterprises: show_your_enterprises_user_menu?,
          showEnterprise: show_your_enterprise_user_menu?,
          showGists: GitHub.gist_enabled?(current_user),
          showOrganizations: show_your_organizations_link?,
          showSponsors: GitHub.sponsors_enabled?,
          showUpgrade: !GitHub.enterprise? && !GitHub.multi_tenant_enterprise?,
          showFeaturesPreviews: !GitHub.enterprise?,
          showEnterpriseSettings: show_enterprise_settings_user_menu?,
        },
        createMenu: create_menu_props,
        headerLogo: {
          href: home_url,
          hotkey: hotkeys_for(current_user, :global, :go_to_dashboard),
          'aria-label': "Homepage #{GitHub.site_heading(enterprise_managed_user: enterprise_managed_user?)}"
        },
        notifications: {
          hotkey: hotkeys_for(current_user, :global, :go_to_notifications),
          indicatorMode: :none,
          websocketChannel: live_update_view_channel(GitHub::WebSocket::Channels.notifications_changed(current_user)),
          fetchIndicatorSrc: notifications_indicator_path,
          fetchIndicatorEnabled: true
        },
        issues: {
          href: all_issues_url,
          hotkey: hotkeys_for(current_user, :global, :go_to_your_issues)
        },
        pulls: {
          href: all_pulls_url,
          hotkey: hotkeys_for(current_user, :global, :go_to_your_pull_requests)
        },
        contributedRepos: {
          show: repos_contributed_page_enabled?,
          href: repos_contributed_page_enabled? ? repositories_finder_url : nil,
          hotkey: hotkeys_for(current_user, :global, :go_to_your_contributed_repos)
        },
        copilot: {
          show: show_copilot_buttons?,
          showCopilotTitle: show_copilot_title?,
          showAgentsButton: show_agents_button?,
          agentsPanel: {
            popoverAvailable: show_copilot_coding_agent_entry_point_popover?,
            repository: repo_for_react,
            showNotification: show_copilot_notification?
          }
        },
        search: {
          show: !hide_search?,
          searchHotkey: hotkeys_for(current_user, :global, :search_bar_focus),
          showCommandPalette: command_palette_enabled?,
          isSearchPage: is_search_page?,
        },
        enterpriseBanner: enterprise_managed_banner_props
      }
    end

    def enterprise_managed_banner_props
      if !show_enterprise_managed_header?
        return { show: false }
      end

      {
        show: true,
        href: enterprise_url(enterprise_managed_business),
        businessName: enterprise_managed_business.name,
        isFirstEmuOwner: current_user.is_first_emu_owner?,
        viewingAsLogin: current_user.display_login,
        showDataResidency: show_data_residency?,
        dataResidencyRegion: GitHub::Config::Proxima.current_region_label
      }
    end

    memoize def enterprise_managed_business
      current_user.enterprise_managed_business
    end

    memoize def show_enterprise_managed_header?
      return false unless logged_in?
      return false unless current_user.is_enterprise_managed?
      enterprise_managed_business.present?
    end

    memoize def show_data_residency?
      show_enterprise_managed_header? &&
      GitHub.multi_tenant_enterprise? &&
      GitHub::Config::Proxima.current_region_label.present?
    end

    def is_search_page?
      current_page?(search_path) || (current_repository.present? && current_page?(repo_search_path(current_repository.owner, current_repository)))
    end

    def cls_fixes_enabled?
      FeatureFlag.vexi.enabled?(:global_nav_cls_fixes, current_user, default: false)
    end

    def show_copilot_buttons?
      GitHub.copilot_enabled? && logged_in? && request_path(request) != copilot_immersive_path && copilot_enabled?
    end

    def show_copilot_title?
      feature_enabled_globally_or_for_user?(feature_name: :copilot_f2p)
    end

    def show_agents_button?
      feature_enabled_globally_or_for_user?(feature_name: :copilot_global_agent_button) && copilot_coding_agent_enabled?
    end

    def request_path(request)
      # The following is to grab the first non-empty string after splitting on "/" so that
      # both production and test environments are happy.
      # In production: request_path = "/copilot"
      # In tests: request_path = "//copilot"
      "/#{request&.path.to_s.split("/").find(&:present?)}"
    end

    def repo_for_react
      return nil if @current_repository.nil?

      attrs = {
        id: @current_repository.id,
        name: @current_repository.name,
        owner_login: @current_repository.owner_display_login
      }

      Repos::ReactPayload.camelize_keys(attrs)
    end

    def copilot_coding_agent_enabled?
      with_database_error_fallback(fallback: false) do
        Copilot::Public::User.new(current_user).swe_agent_enabled?
      end
    end

    def copilot_enabled?
      with_database_error_fallback(fallback: false) { helpers.show_copilot_chat_entrypoint? }
    end

    def show_copilot_coding_agent_entry_point_popover?
      with_database_error_fallback(fallback: false) do
        CopilotSessions::Public.show_copilot_coding_agent_entry_point_popover?(current_user)
      end
    end

    def show_copilot_notification?
      if !FeatureFlag.vexi.enabled?(:copilot_coding_agent_task_indicator, current_user, default: false)
        return false
      elsif current_user.settings.get(:copilot_coding_agent_number_running_tasks) > 0
        return true
      end

      false
    end
  end
end
