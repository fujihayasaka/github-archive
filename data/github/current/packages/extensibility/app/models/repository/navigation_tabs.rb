# typed: true
# frozen_string_literal: true

class Repository
  class NavigationTabs < ContextRegion::LocalNavigation::NavigationTabs
    include AnalyticsHelper
    include UrlHelpers
    include UrlHelper
    include GitHub::Memoizer
    include GitHub::ResilienceMixin

    attr_reader :repository, :user_can_write_wiki, :current_branch_or_tag_name

    TAB_METADATA = {
      code: {
        icon: "code",
        label: "Code",
        hotkey: "g c",
        selected_links: [:repo_source, :repo_downloads, :repo_commits, :repo_releases, :repo_tags, :repo_branches, :repo_packages, :repo_deployments, :repo_attestations],
      },
      issues: {
        icon: "issue-opened",
        label: "Issues",
        hotkey: "g i",
        selected_links: [:repo_issues, :repo_labels, :repo_milestones],
      },
      pull_requests: {
        icon: "git-pull-request",
        label: "Pull requests",
        hotkey: "g p",
        selected_links: [:repo_pulls, :checks],
      },
      discussions: {
        icon: "comment-discussion",
        label: "Discussions",
        hotkey: "g g",
        selected_links: [:repo_discussions],
      },
      actions: {
        icon: "play",
        label: "Actions",
        hotkey: "g a",
        selected_links: [:repo_actions],
      },
      projects: {
        icon: "table",
        label: "Projects",
        hotkey: "g b",
        selected_links: [:repo_projects, :new_repo_project, :repo_project],
      },
      models: {
        icon: "ai-model",
        label: "Models",
        hotkey: "g m",
        selected_links: [:repo_models, :repo_models_prompts, :repo_models_playground],
      },
      agents: {
        icon: "copilot",
        label: "Agents",
        hotkey: "g e",
        selected_links: [:repo_agents, :repo_agents_task],
      },
      wiki: {
        icon: "book",
        label: "Wiki",
        hotkey: "g w",
        selected_links: [:repo_wiki],
      },
      security: {
        icon: "shield",
        label: "Security",
        hotkey: "g s",
        selected_links: [:security, :overview, :alerts, :policy, :token_scanning, :code_scanning],
      },
      insights: {
        icon: "graph",
        label: "Insights",
        selected_links: [:repo_graphs, :repo_contributors, :dependency_graph, :dependabot_updates, :pulse, :people, :community],
      },
      settings: {
        icon: "gear",
        label: "Settings",
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
          :repository_environments,
          :role_details,
          :secrets_settings_actions,
          :secrets_settings_codespaces,
          :secrets_settings_dependabot,
          :secrets,
          :security_analysis,
          :security_products,
        ],
      },
    }.freeze

    def initialize(repository:, current_user: nil, user_can_write_wiki: nil, current_branch_or_tag_name: nil)
      @repository = repository
      @user_can_write_wiki = user_can_write_wiki
      @current_branch_or_tag_name = current_branch_or_tag_name
      super(current_user: current_user)
    end

    def links(security_counter: nil)
      tabs = [code_tab]

      if show_issues?
        tabs << issues_tab
      end

      tabs << pull_requests_tab

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
      !repo_is_advisory_workspace?
    end

    memoize def load_security_tab_count?
      return false unless show_security?

      with_database_error_fallback(fallback: false) do
        security_view.show_dependabot_alerts? ||
          security_view.show_advisories? ||
          security_view.show_token_scanning? ||
          security_view.show_code_scanning?
      end
    end

    def show_security_lazy_count?(security_counter)
      security_counter.present?
    end

    memoize def show_actions?
      with_database_error_fallback(fallback: false) do
        repository.show_actions?
      end
    end

    memoize def repo_is_advisory_workspace?
      return false unless GitHub.repository_advisories_enabled?

      repository.advisory_workspace?
    end

    memoize def show_config?
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

    memoize def show_discussions?
      show_discussions_for_repo?(repository)
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

    memoize def show_insights?
      return false if repo_is_advisory_workspace?
      plan_supports_insights? || GitHub.dependency_graph_enabled?
    end

    memoize def show_issues?
      repository.has_issues?
    end

    memoize def show_projects?
      with_database_error_fallback(fallback: false) do
        return false if repo_is_advisory_workspace?
        repository_memex_projects_enabled = repository.repository_memex_projects_enabled?
        repository.owner.organization? ? repository_memex_projects_enabled && repository.owner.organization_projects_enabled? : repository_memex_projects_enabled
      end
    end

    memoize def show_models?
      return false unless GitHub.models_enabled?

      GitHubModels::Repository.new(repository: repository).models_enabled_for_repo?
    end

    memoize def show_agents?
      return false unless logged_in?
      return false unless current_user&.feature_flag_enabled?(:repo_agents_view, default: false)

      repository.copilot_swe_agent_enabled?(current_user)
    end

    memoize def show_wiki?
      with_database_error_fallback(fallback: false) do
        repository.show_wiki?(current_user, user_can_write_wiki: user_can_write_wiki)
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
      if !open_projects_counter_caching_feature_flags_enabled?(repository)
        with_database_error_fallback(fallback: 0) do
          repository.open_memex_projects_count_for(current_user)
        end
      else
        Planning.domain.open_memex_projects_count_for_repo(repository, current_user)
      end
    end

    memoize def can_manage_code_security_settings?
      return false unless logged_in?
      if repository.show_config_authzd_enabled?
        repository.batched_layout_authzd_permissions(current_user, :can_manage_security_products)
      else
        SecurityProduct::Permissions::RepoAuthz.new(repository, actor: current_user).can_manage_repo_security_products?
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
      meta = TAB_METADATA[:code]
      Site::Header::UnderlineNavTab.new(
        data: { hotkey: meta[:hotkey] },
        highlight: meta[:selected_links] || [],
        href: repository_path(repository, current_branch_or_tag_name),
        icon: meta[:icon],
        text: meta[:label]
      )
    end

    memoize def issues_tab
      meta = TAB_METADATA[:issues]
      Site::Header::UnderlineNavTab.new(
        count: open_issue_count,
        data: { hotkey: meta[:hotkey], react_nav: "issues-react" },
        highlight: meta[:selected_links] || [],
        href: issues_path(repository.owner, repository),
        icon: meta[:icon],
        text: meta[:label]
      )
    end

    memoize def pull_requests_tab
      meta = TAB_METADATA[:pull_requests]
      Site::Header::UnderlineNavTab.new(
        count: open_pull_request_count,
        data: { hotkey: meta[:hotkey] },
        highlight: meta[:selected_links] || [],
        href: pull_requests_path(repository.owner, repository),
        icon: meta[:icon],
        text: meta[:label],
      )
    end

    memoize def discussions_tab
      meta = TAB_METADATA[:discussions]
      Site::Header::UnderlineNavTab.new(
        data: { hotkey: meta[:hotkey] }.merge(analytics_click_attributes(category: "Discussions", action: "clicked", label: "ref_cta:Discussions;ref_loc:navigation_helper")),
        highlight: meta[:selected_links] || [],
        href: discussions_path(repository.owner, repository),
        icon: meta[:icon],
        text: meta[:label]
      )
    end

    memoize def actions_tab
      meta = TAB_METADATA[:actions]
      Site::Header::UnderlineNavTab.new(
        data: { hotkey: meta[:hotkey] }.merge(analytics_click_attributes(category: "Actions", action: "clicked", label: "ref_cta:Actions;ref_loc:navigation_helper")),
        highlight: meta[:selected_links] || [],
        href: actions_path(repository.owner, repository),
        icon: meta[:icon],
        text: meta[:label]
      )
    end

    memoize def projects_tab
      meta = TAB_METADATA[:projects]
      Site::Header::UnderlineNavTab.new(
        count: open_project_count,
        data: { hotkey: meta[:hotkey] },
        highlight: meta[:selected_links] || [],
        href: repo_projects_path(repository.owner, repository),
        icon: meta[:icon],
        text: meta[:label]
      )
    end

    memoize def models_tab
      meta = TAB_METADATA[:models]
      Site::Header::UnderlineNavTab.new(
        data: { hotkey: meta[:hotkey] },
        highlight: meta[:selected_links] || [],
        href: repo_models_path(repository.owner, repository),
        icon: meta[:icon],
        text: meta[:label]
      )
    end

    memoize def agents_tab
      meta = TAB_METADATA[:agents]
      Site::Header::UnderlineNavTab.new(
        data: { hotkey: meta[:hotkey] },
        highlight: meta[:selected_links] || [],
        href: repo_agents_path(repository.owner, repository),
        icon: meta[:icon],
        text: meta[:label]
      )
    end

    memoize def wiki_tab
      meta = TAB_METADATA[:wiki]
      Site::Header::UnderlineNavTab.new(
        data: { hotkey: meta[:hotkey] },
        highlight: meta[:selected_links] || [],
        href: wikis_path(repository.owner, repository),
        icon: meta[:icon],
        text: meta[:label]
      )
    end

    def security_tab
      meta = TAB_METADATA[:security]

      count = if load_security_tab_count?
        with_database_error_fallback(fallback: 0) do
          security_view.security_count
        end
      else
        nil
      end

      Site::Header::UnderlineNavTab.new(
        data: { hotkey: meta[:hotkey] },
        highlight: meta[:selected_links] || [],
        href: repository_security_overview_path(repository.owner, repository),
        icon: meta[:icon],
        text: meta[:label],
        count: count
      )
    end

    # Rails-rendered security_tabs use a proc-based counter for async loading
    def security_tab_lazy_count(security_counter)
      meta = TAB_METADATA[:security]

      Site::Header::UnderlineNavTab.new(
        data: { hotkey: meta[:hotkey] },
        highlight: meta[:selected_links] || [],
        href: repository_security_overview_path(repository.owner, repository),
        icon: meta[:icon],
        text: meta[:label],
        count: security_counter
      )
    end

    memoize def insights_tab
      meta = TAB_METADATA[:insights]
      Site::Header::UnderlineNavTab.new(
        highlight: meta[:selected_links] || [],
        href: plan_supports_insights? ? gh_pulse_path(repository) : gh_network_dependencies_path(repository),
        icon: meta[:icon],
        text: meta[:label]
      )
    end

    memoize def settings_tab
      meta = TAB_METADATA[:settings]
      Site::Header::UnderlineNavTab.new(
        highlight: meta[:selected_links] || [],
        href: edit_repository_path(repository.owner, repository),
        icon: meta[:icon],
        text: meta[:label]
      )
    end

    memoize def settings_security_analysis_tab
      meta = TAB_METADATA[:settings]
      Site::Header::UnderlineNavTab.new(
        href: repository_security_and_analysis_path(repository.owner, repository),
        icon: meta[:icon],
        text: meta[:label]
      )
    end

    memoize def custom_tabs
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

    memoize def plan_supports_insights?
      repository.plan_supports?(:insights)
    end

    def has_repository_permission?(*permissions)
      permissions.include?(current_repository_permission_level)
    end

    memoize def current_repository_permission_level
      repository.async_action_or_role_level_for(current_user, include_custom_roles: false).sync
    end
  end
end
