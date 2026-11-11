# typed: true
# frozen_string_literal: true

class Repository
  class NavigationTabs < ContextRegion::LocalNavigation::NavigationTabs
    include AnalyticsHelper
    include UrlHelpers
    include UrlHelper
    include GitHub::Memoizer
    include GitHub::ResilienceMixin

    attr_reader :repository, :user_can_write_wiki, :current_branch_or_tag_name, :tab_popovers, :on_repo_code_page

    TAB_METADATA = {
      code: {
        icon: "code",
        label: "Code",
        hotkey: "g c",
        command_id: "repositories:go-to-code",
        selected_links: [:repo_source, :repo_downloads, :repo_commits, :repo_releases, :repo_tags, :repo_branches, :repo_packages, :repo_deployments, :repo_attestations],
      },
      issues: {
        icon: "issue-opened",
        label: "Issues",
        hotkey: "g i",
        command_id: "repositories:go-to-issues",
        selected_links: [:repo_issues, :repo_labels, :repo_milestones],
      },
      pull_requests: {
        icon: "git-pull-request",
        label: "Pull requests",
        hotkey: "g p",
        command_id: "repositories:go-to-pull-requests",
        selected_links: [:repo_pulls, :checks],
      },
      discussions: {
        icon: "comment-discussion",
        label: "Discussions",
        hotkey: "g g",
        command_id: "repositories:go-to-discussions",
        selected_links: [:repo_discussions],
      },
      actions: {
        icon: "play",
        label: "Actions",
        hotkey: "g a",
        command_id: "repositories:go-to-actions",
        selected_links: [:repo_actions],
      },
      projects: {
        icon: "table",
        label: "Projects",
        hotkey: "g b",
        command_id: "repositories:go-to-projects",
        selected_links: [:repo_projects, :new_repo_project, :repo_project],
      },
      models: {
        icon: "ai-model",
        label: "Models",
        hotkey: "g m",
        command_id: "repositories:go-to-models",
        selected_links: [:repo_models, :repo_models_prompts, :repo_models_playground],
      },
      agents: {
        icon: "agent",
        label: "Agents",
        hotkey: "g e",
        command_id: "repositories:go-to-agents",
        selected_links: [:repo_agents, :repo_agents_task],
      },
      wiki: {
        icon: "book",
        label: "Wiki",
        hotkey: "g w",
        command_id: "repositories:go-to-wiki",
        selected_links: [:repo_wiki],
      },
      security: {
        icon: "shield",
        label: "Security",
        hotkey: "g s",
        command_id: "repositories:go-to-security",
        selected_links: [:security, :overview, :alerts, :policy, :token_scanning, :code_scanning],
      },
      insights: {
        icon: "graph",
        label: "Insights",
        command_id: "repositories:go-to-insights",
        selected_links: [:repo_graphs, :repo_contributors, :dependency_graph, :dependabot_updates, :pulse, :people, :community],
      },
      settings: {
        icon: "gear",
        label: "Settings",
        command_id: "repositories:go-to-settings",
        selected_links: [
          :code_review_limits,
          :code_quality,
          :codespaces_repository_settings,
          :collaborators,
          :custom_tabs,
          :github_models_repo_settings,
          :hooks,
          :integration_installations,
          :interaction_limits,
          :issue_template_editor,
          :key_links_settings,
          :license_policy,
          :notifications,
          :repo_announcements,
          :repo_branch_settings,
          :repo_custom_properties,
          :repo_keys_settings,
          :repo_pages_settings,
          :repo_protected_tags_settings,
          :repo_rule_insights,
          :repo_rule_insights_dashboard,
          :repo_rules_bypass_requests,
          :repo_rulesets,
          :repo_settings_copilot_coding_guidelines,
          :repo_settings_copilot_content_exclusion,
          :repo_settings_copilot_swe_agent,
          :repo_settings,
          :reported_content,
          :repository_actions_settings_add_new_runner,
          :repository_actions_settings_general,
          :repository_actions_settings_runner_details,
          :repository_actions_settings_runners,
          :repository_actions_settings,
          :repository_actions_settings_policies,
          :repository_actions_settings_oidc_configuration,
          :repository_environments,
          :role_details,
          :secrets_settings_actions,
          :secrets_settings_agents,
          :secrets_settings_codespaces,
          :secrets_settings_dependabot,
          :secrets,
          :security_analysis,
          :security_products,
        ],
      },
    }.freeze

    def initialize(repository:, current_user: nil, user_can_write_wiki: nil, current_branch_or_tag_name: nil, tab_popovers: {}, on_repo_code_page: false, current_copilot_user: nil)
      @repository = repository
      @user_can_write_wiki = user_can_write_wiki
      @current_branch_or_tag_name = current_branch_or_tag_name
      @tab_popovers = tab_popovers
      @on_repo_code_page = on_repo_code_page
      @current_copilot_user = current_copilot_user
      super(current_user: current_user)
    end

    def links(security_counter: nil)
      tabs = [code_tab]

      if show_issues?
        tabs << issues_tab
      end

      if show_pull_requests?
        tabs << pull_requests_tab
      end

      if show_agents?
        tabs << agents_tab
      end

      with_database_error_fallback do
        tabs << discussions_tab if show_discussions?
      end

      if show_actions?
        tabs << actions_tab
      end

      if show_projects?
        tabs << projects_tab
      end

      if show_models?
        tabs << models_tab
      end

      with_database_error_fallback do
        if show_wiki?
          tabs << wiki_tab
        end
      end

      if react_global_nav_enabled?
        tabs << security_tab if show_security?
      else
        if show_security_lazy_count?(security_counter) && !repo_is_advisory_workspace?
          tabs << security_tab_lazy_count(security_counter)
        end
      end

      tabs << insights_tab if show_insights?

      with_database_error_fallback do
        if show_config?
          tabs << settings_tab
        elsif repository.owner.organization? && can_manage_code_security_settings?
          tabs << settings_security_analysis_tab
        end
      end

      tabs.concat(custom_tabs)
    end

    # Alias for compatibility with ContextRegion::LocalNavigation::TabPayload
    def tabs
      links
    end

    # Security tab is always shown except on advisory workspace repos
    memoize def show_security?
      record_predicate_timing(:show_security) do
        !repo_is_advisory_workspace?
      end
    end

    memoize def load_security_tab_count?
      record_predicate_timing(:load_security_tab_count) do
        return false unless show_security?

        with_database_error_fallback(fallback: false) do
          security_view.show_dependabot_alerts? ||
            security_view.show_advisories? ||
            security_view.show_token_scanning? ||
            security_view.show_code_scanning?
        end
      end
    end

    def show_security_lazy_count?(security_counter)
      security_counter.present?
    end

    memoize def show_actions?
      record_predicate_timing(:show_actions) do
        with_database_error_fallback(fallback: false) do
          repository.show_actions?
        end
      end
    end

    memoize def repo_is_advisory_workspace?
      record_predicate_timing(:repo_is_advisory_workspace) do
        return false unless GitHub.repository_advisories_enabled?

        repository.advisory_workspace?
      end
    end

    memoize def show_config?
      record_predicate_timing(:show_config) do
        return false unless logged_in?

        if repository.show_config_authzd_enabled?
          repository.batched_layout_authzd_permissions(current_user, :show_config)
        else
          return false if repo_is_advisory_workspace?
          return true if has_repository_permission?(:maintain, :admin)
          return false unless repository.owner.organization?
          return false if repository.private?
          repository.owner.moderator?(current_user)
        end
      end
    end

    memoize def show_discussions?
      record_predicate_timing(:show_discussions) do
        show_discussions_for_repo?(repository)
      end
    end

    def show_discussions_for_repo?(repo)
      return false unless GitHub.discussions_available_on_platform?
      return false unless repo.present?

      # Show tab if discussions feature is enabled for this repo
      return true if repo.discussions_active?

      # Show unboxing tab to users who have permissions to enable discussions, on repos where:
      # * The repo is public.
      # * Discussions have never been enabled before.
      # * The user has not dismissed the notice.
      return false unless logged_in?
      return false if repo.private?
      return false if repo.discussions_ever_active?

      issue_count = with_database_error_fallback(fallback: 0) do
        open_issue_count
      end

      return false unless repo.unboxing_minimum_issue_count?(issue_count)

      if repo.show_config_authzd_enabled?
        # Check authzd batched permissions if we're making a request to authzd anyway.
        return false unless repo.batched_layout_authzd_permissions(current_user, :can_toggle_discussions_setting)
      else
        # Otherwise, check permissions directly.
        # This is an antipattern :-( but it saves us ~20ms on every repository page.
        return false unless has_repository_permission?(:maintain, :admin)
      end

      return false if current_user&.dismissed_repository_notice?("discussions_tab", repository_id: repo.id)

      true
    end

    def turbo_frame
      "repo-content-turbo-frame"
    end

    memoize def show_insights?
      record_predicate_timing(:show_insights) do
        return false if repo_is_advisory_workspace?
        plan_supports_insights? || GitHub.dependency_graph_enabled?
      end
    end

    memoize def show_issues?
      record_predicate_timing(:show_issues) do
        repository.has_issues?
      end
    end

    memoize def show_pull_requests?
      record_predicate_timing(:show_pull_requests) do
        PullRequestActivationConfig.new(repository).pull_requests_enabled?
      end
    end

    memoize def show_projects?
      record_predicate_timing(:show_projects) do
        with_database_error_fallback(fallback: false) do
          return false if repo_is_advisory_workspace?
          repository_memex_projects_enabled = repository.repository_memex_projects_enabled?
          repository.owner.organization? ? repository_memex_projects_enabled && repository.owner.organization_projects_enabled? : repository_memex_projects_enabled
        end
      end
    end

    memoize def show_models?
      record_predicate_timing(:show_models) do
        return false unless GitHub.models_enabled?
        return false if repo_is_advisory_workspace?

        GitHubModels::Repository.new(repository: repository).models_enabled_for_repo?
      end
    end

    memoize def show_agents?
      record_predicate_timing(:show_agents) do
        return false unless logged_in?
        return false if repo_is_advisory_workspace?

        # New flow: show tab to any Copilot user if owner has CCA enabled for repo
        if FeatureFlag.vexi.enabled?(:repo_agents_show_upgrade_slate, current_user, default: false)
          copilot_user = @current_copilot_user || Copilot::Public::User.new(T.must(current_user))
          return false unless copilot_user.has_copilot_access?
          return false unless copilot_user.show_copilot_functionality?
          repository.owner&.copilot_swe_agent_enabled_for?(repository)
        else
          # Old flow: check if CCA is enabled for the repo and this specific viewer through their policy
          repository.copilot_swe_agent_enabled?(current_user)
        end
      end
    end

    memoize def show_wiki?
      record_predicate_timing(:show_wiki) do
        with_database_error_fallback(fallback: false) do
          repository.show_wiki?(current_user, user_can_write_wiki: user_can_write_wiki)
        end
      end
    rescue GitHub::Spokes::ClientError
      false
    end

    memoize def open_issue_count
      Issues.domain.open_issue_count_for_repo(repository, current_user, cached: true)
    end

    def open_pull_requests_count_caching_enabled?(repo)
      # The "navbar_counter_caching_pull_requests_count" feature flag controls for which repositories
      # should use the cache.
      FeatureFlag.vexi.enabled?(:navbar_counter_caching_pull_requests_count, repo, default: false)
    end

    memoize def open_pull_request_count
      if !open_pull_requests_count_caching_enabled?(repository)
        with_database_error_fallback(fallback: 0) do
          repository.open_pull_request_count_for(current_user) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        end
      else
        PullRequests.domain.open_pull_request_count_for_repo(repository, current_user)
      end
    end

    def open_projects_counter_caching_feature_flags_enabled?(repo)
      # The "navbar_counter_caching_project_count" feature flag controls for which repositories
      # should use the cache.
      FeatureFlag.vexi.enabled?(:navbar_counter_caching_project_count, repo, default: false)
    end

    memoize def open_project_count
      return nil if FeatureFlag.vexi.enabled?(:global_nav_exclude_project_count, repository, default: false)

      if !open_projects_counter_caching_feature_flags_enabled?(repository)
        with_database_error_fallback(fallback: 0) do
          repository.open_memex_projects_count_for(current_user)
        end
      else
        Planning.domain.open_memex_projects_count_for_repo(repository, current_user)
      end
    end

    memoize def can_manage_code_security_settings?
      record_predicate_timing(:can_manage_code_security_settings) do
        return false unless logged_in?
        if repository.show_config_authzd_enabled?
          repository.batched_layout_authzd_permissions(current_user, :can_manage_security_products)
        else
          SecurityProduct::Permissions::RepoAuthz.new(repository, actor: current_user).can_manage_repo_security_products?
        end
      end
    end

    sig { returns(T::Boolean) }
    memoize def security_alert_count_caching_enabled?
      FeatureFlag.vexi.enabled?(:global_nav_security_count_cache, repository, default: false)
    end

    sig { returns(T.nilable(Integer)) }
    memoize def security_alert_count
      if !security_alert_count_caching_enabled?
        # load_security_tab_count? performs database queries, so we only want to call it when not using the cached value
        return nil unless load_security_tab_count?

        with_database_error_fallback(fallback: 0) do
          security_view.security_count
        end
      else
        return nil if repository.spammy? || current_user&.spammy?

        SecurityProducts.domain.security_alert_count_for_repo(repository, current_user)
      end
    end

    memoize def security_view
      Navigation::Repository::SecurityView.new(current_user: current_user, current_repository: repository)
    end

    private

    def logged_in?
      current_user.present?
    end

    memoize def code_tab
      record_tab_timing(:code) do
        meta = TAB_METADATA[:code]
        Site::Header::UnderlineNavTab.new(
          data: { hotkey: meta[:hotkey], command_id: meta[:command_id], react_nav: "code-view", react_nav_anchor: "code-view-repo-link" },
          highlight: meta[:selected_links] || [],
          href: repository_path(repository, current_branch_or_tag_name),
          icon: meta[:icon],
          text: meta[:label]
        )
      end
    end

    memoize def issues_tab
      record_tab_timing(:issues) do
        meta = TAB_METADATA[:issues]
        Site::Header::UnderlineNavTab.new(
          count: open_issue_count,
          data: { hotkey: meta[:hotkey], command_id: meta[:command_id], react_nav: "issues-react" },
          highlight: meta[:selected_links] || [],
          href: issues_path(repository.owner, repository),
          icon: meta[:icon],
          text: meta[:label]
        )
      end
    end

    memoize def pull_requests_tab
      record_tab_timing(:pull_requests) do
        meta = TAB_METADATA[:pull_requests]
        Site::Header::UnderlineNavTab.new(
          count: open_pull_request_count,
          data: { hotkey: meta[:hotkey], command_id: meta[:command_id] },
          highlight: meta[:selected_links] || [],
          href: pull_requests_path(repository.owner, repository),
          icon: meta[:icon],
          text: meta[:label],
        )
      end
    end

    memoize def discussions_tab
      record_tab_timing(:discussions) do
        meta = TAB_METADATA[:discussions]
        Site::Header::UnderlineNavTab.new(
          data: { hotkey: meta[:hotkey], command_id: meta[:command_id] }.merge(analytics_click_attributes(category: "Discussions", action: "clicked", label: "ref_cta:Discussions;ref_loc:navigation_helper")),
          highlight: meta[:selected_links] || [],
          href: discussions_path(repository.owner, repository),
          icon: meta[:icon],
          text: meta[:label]
        )
      end
    end

    memoize def actions_tab
      record_tab_timing(:actions) do
        meta = TAB_METADATA[:actions]
        Site::Header::UnderlineNavTab.new(
          data: { hotkey: meta[:hotkey], command_id: meta[:command_id] }.merge(analytics_click_attributes(category: "Actions", action: "clicked", label: "ref_cta:Actions;ref_loc:navigation_helper")),
          highlight: meta[:selected_links] || [],
          href: actions_path(repository.owner, repository),
          icon: meta[:icon],
          text: meta[:label]
        )
      end
    end

    memoize def projects_tab
      counts_enabled = !FeatureFlag.vexi.enabled?(:global_nav_exclude_project_count, repository, default: false)
      record_tab_timing(:projects, ["counts_enabled:#{counts_enabled}"]) do
        meta = TAB_METADATA[:projects]
        Site::Header::UnderlineNavTab.new(
          count: open_project_count,
          data: { hotkey: meta[:hotkey], command_id: meta[:command_id] },
          highlight: meta[:selected_links] || [],
          href: repo_projects_path(repository.owner, repository),
          icon: meta[:icon],
          text: meta[:label]
        )
      end
    end

    memoize def models_tab
      record_tab_timing(:models) do
        meta = TAB_METADATA[:models]
        Site::Header::UnderlineNavTab.new(
          data: { hotkey: meta[:hotkey], command_id: meta[:command_id] },
          highlight: meta[:selected_links] || [],
          href: repo_models_path(repository.owner, repository),
          icon: meta[:icon],
          text: meta[:label]
        )
      end
    end

    memoize def agents_tab
      record_tab_timing(:agents) do
        meta = TAB_METADATA[:agents]
        Site::Header::UnderlineNavTab.new(
          data: { hotkey: meta[:hotkey], command_id: meta[:command_id] },
          highlight: meta[:selected_links] || [],
          href: repo_agents_path(repository.owner, repository, author: current_user&.display_login),
          icon: meta[:icon],
          text: meta[:label]
        )
      end
    end

    memoize def wiki_tab
      record_tab_timing(:wiki) do
        meta = TAB_METADATA[:wiki]
        Site::Header::UnderlineNavTab.new(
          data: { hotkey: meta[:hotkey], command_id: meta[:command_id] },
          highlight: meta[:selected_links] || [],
          href: wikis_path(repository.owner, repository),
          icon: meta[:icon],
          text: meta[:label]
        )
      end
    end

    def security_tab
      tags = [
        "cached:#{security_alert_count_caching_enabled?}",
        "spammy_repo:#{repository.spammy?}",
        "spammy_user:#{current_user&.spammy? || false}"
      ]

      record_tab_timing(:security, tags) do
        meta = TAB_METADATA[:security]

        Site::Header::UnderlineNavTab.new(
          data: { hotkey: meta[:hotkey], command_id: meta[:command_id] },
          highlight: meta[:selected_links] || [],
          href: repository_security_overview_path(repository.owner, repository),
          icon: meta[:icon],
          text: security_tab_title(meta),
          count: security_alert_count,
          popover_data: security_tab_popover_data
        )
      end
    end

    # Rails-rendered security_tabs use a proc-based counter for async loading
    def security_tab_lazy_count(security_counter)
      record_tab_timing(:security_lazy_count) do
        meta = TAB_METADATA[:security]

        Site::Header::UnderlineNavTab.new(
          data: { hotkey: meta[:hotkey], command_id: meta[:command_id] },
          highlight: meta[:selected_links] || [],
          href: repository_security_overview_path(repository.owner, repository),
          icon: meta[:icon],
          text: security_tab_title(meta),
          count: security_counter
        )
      end
    end

    memoize def insights_tab
      record_tab_timing(:insights) do
        meta = TAB_METADATA[:insights]
        Site::Header::UnderlineNavTab.new(
          data: { command_id: meta[:command_id] },
          highlight: meta[:selected_links] || [],
          href: plan_supports_insights? ? gh_pulse_path(repository) : gh_network_dependencies_path(repository),
          icon: meta[:icon],
          text: meta[:label]
        )
      end
    end

    memoize def settings_tab
      record_tab_timing(:settings) do
        meta = TAB_METADATA[:settings]
        Site::Header::UnderlineNavTab.new(
          data: { command_id: meta[:command_id] },
          highlight: meta[:selected_links] || [],
          href: edit_repository_path(repository.owner, repository),
          icon: meta[:icon],
          text: meta[:label],
          popover_data: settings_tab_popover_data
        )
      end
    end

    memoize def settings_security_analysis_tab
      record_tab_timing(:settings_security_analysis) do
        meta = TAB_METADATA[:settings]
        Site::Header::UnderlineNavTab.new(
          href: repository_security_and_analysis_path(repository.owner, repository),
          icon: meta[:icon],
          text: meta[:label],
          popover_data: settings_tab_popover_data
        )
      end
    end

    memoize def custom_tabs
      record_tab_timing(:custom_tabs) do
        if GitHub.custom_tabs_enabled? && repository.tabs.present?
          repository.tabs.sort_by(&:anchor).map do |tab|
            Site::Header::UnderlineNavTab.new(
              href: tab.url,
              icon: "link-external",
              text: tab.anchor,
              data_turbo_frame: false
            )
          end
        else
          []
        end
      end
    end

    memoize def plan_supports_insights?
      repository.plan_supports?(:insights)
    end

    def has_repository_permission?(*permissions)
      permissions.include?(current_repository_permission_level)
    end

    memoize def current_repository_permission_level
      repository.async_action_or_role_level_for(current_user, include_custom_roles: false).sync
    end

    sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
    memoize def settings_tab_popover_data
      return nil unless on_repo_code_page
      return nil unless can_manage_code_security_settings?

      case @tab_popovers[:settings]
      when "secret-scanning-alerts"
        return nil if SecretScanning::Features::Repo::TokenScanning.new(repository).enabled?

        build_popover(
          header: "Get secret scanning working",
          message: "Enable secret scanning under settings to start finding and blocking exposed passwords and sensitive data in your repository.",
          cta_label: "Enable in settings",
          cta_url: repository_security_and_analysis_path(repository.owner, repository),
          intent: "secret-scanning-alerts"
        )
      when "code-scanning-alerts"
        return nil if repository.code_scanning_enabled?

        build_popover(
          header: "Get code scanning working",
          message: "Enable code scanning under settings to start finding and fixing vulnerabilities and coding errors in your repository.",
          cta_label: "Enable in settings",
          cta_url: repository_security_and_analysis_path(repository.owner, repository),
          intent: "code-scanning-alerts"
        )
      end
    end

    sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
    memoize def security_tab_popover_data
      return nil unless on_repo_code_page
      return nil unless can_manage_code_security_settings?

      case @tab_popovers[:security]
      when "secret-scanning-alerts"
        return nil unless SecretScanning::Features::Repo::TokenScanning.new(repository).enabled?

        build_popover(
          header: "Secret scanning is enabled",
          message: "Secret scanning finds and blocks exposed passwords and sensitive data in your repository. See the results of the latest scan.",
          cta_label: "View secret scanning alerts",
          cta_url: repository_token_scanning_results_path(repository.owner, repository),
          intent: "secret-scanning-alerts"
        )
      when "code-scanning-alerts"
        return nil unless repository.code_scanning_enabled?

        build_popover(
          header: "Code scanning is enabled",
          message: "Code scanning is a security feature that helps you find and fix vulnerabilities and coding errors in your repository.",
          cta_label: "View code scanning alerts",
          cta_url: repository_code_scanning_results_path(repository.owner, repository),
          intent: "code-scanning-alerts"
        )
      end
    end

    sig do
      params(
        header: String,
        message: String,
        cta_label: String,
        cta_url: String,
        intent: String
      ).returns(T::Hash[Symbol, T.untyped])
    end
    def build_popover(header:, message:, cta_label:, cta_url:, intent:)
      {
        header: header,
        message: message,
        cta: {
          label: cta_label,
          href: cta_url,
        },
        analytics: {
          label: cta_label,
          target_url: cta_url,
          view: "/#{repository.name_with_display_owner}?intent=#{intent}",
        },
      }
    end

    def entity_name
      "repository"
    end

    def record_predicate_timing(predicate_name, &block)
      tags = [
        "predicate:#{predicate_name}",
        "logged_in:#{current_user.present?}"
      ]

      GitHub.dogstats.time("navigation_tabs.#{entity_name}.predicate_evaluation", tags: tags, &block)
    end

    def security_tab_title(meta)
      if CodeQuality.combined_security_and_quality_navigation?(repository, user: current_user)
        "Security and quality"
      else
        meta[:label]
      end
    end
  end
end
