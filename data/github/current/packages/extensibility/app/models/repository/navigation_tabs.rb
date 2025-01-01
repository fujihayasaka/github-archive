# typed: true
# frozen_string_literal: true

module Repository::NavigationTabs
  extend T::Helpers
  include AnalyticsHelper
  include UrlHelpers
  include UrlHelper
  include GitHub::Memoizer
  include ActionsControllerMethods
  include GitHub::ResilienceMixin

  requires_ancestor { Repositories::UnderlineNavComponent }

  def links(security_counter: nil)
    tabs = [code_tab]

    if show_issues?
      tabs << issues_tab
    end

    tabs << pull_requests_tab

    with_database_error_fallback do
      tabs << discussions_tab if show_discussions?
    end

    if show_actions?
      tabs << actions_tab
    end

    if show_projects? || show_classic_projects?
      tabs << projects_tab
    end

    if show_wiki?
      tabs << wiki_tab
    end

    tabs << security_tab(security_counter) unless repo_is_advisory_workspace?

    if show_insights?
      tabs << insights_tab
    end

    with_database_error_fallback do
      if show_config?
        tabs << settings_tab
      elsif current_repository.owner.organization? && can_manage_code_security_settings?
        tabs << settings_security_analysis_tab
      end
    end

    tabs.concat(custom_tabs)
  end

  memoize def show_actions?
    with_database_error_fallback(fallback: false) do
      current_repository.show_actions?
    end
  end

  memoize def repo_is_advisory_workspace?
    return false unless GitHub.repository_advisories_enabled?
    current_repository.advisory_workspace?
  end

  memoize def show_config?
    return false unless logged_in?
    if current_repository.show_config_authzd_enabled?
      current_repository.batched_layout_authzd_permissions(current_user, :show_config)
    else
      return false if repo_is_advisory_workspace?
      return true if has_repository_permission?(:maintain, :admin)
      return false unless current_repository.owner.organization?
      return false if current_repository.private?
      current_repository.owner.moderator?(current_user)
    end
  end

  memoize def show_discussions?
    show_discussions_for_repo?(current_repository)
  end

  memoize def magic_shell
    MagicShell.new(current_user, current_repository)
  end

  def show_discussions_for_repo?(repository)
    return false unless GitHub.discussions_available_on_platform?
    return false unless repository.present?
    # Show tab if discussions feature is enabled for this repo
    return true if repository.discussions_active?

    # Show unboxing tab to users who have permissions to enable discussions, on repos where:
    # * The repo is public.
    # * Discussions have never been enabled before.
    # * The user has not dismissed the notice.
    return false unless logged_in?
    return false if repository.private?
    return false if repository.discussions_ever_active?

    issue_count = with_database_error_fallback(fallback: 0) do
      repository.open_issue_count_for(current_user)
    end

    return false unless repository.unboxing_minimum_issue_count?(issue_count)

    if repository.show_config_authzd_enabled?
      # Check authzd batched permissions if we're making a request to authzd anyway.
      return false unless repository.batched_layout_authzd_permissions(current_user, :can_toggle_discussions_setting)
    else
      # Otherwise, check permissions directly.
      # This is an antipattern :-( but it saves us ~20ms on every repository page.
      return false unless has_repository_permission?(:maintain, :admin)
    end

    return false if current_user.dismissed_repository_notice?("discussions_tab", repository_id: repository.id)

    true
  end

  memoize def show_insights?
    return false if repo_is_advisory_workspace?
    plan_supports_insights? || GitHub.dependency_graph_enabled?
  end

  memoize def show_issues?
    current_repository.has_issues?
  end

  memoize def show_projects?
    with_database_error_fallback(fallback: false) do
      return false if repo_is_advisory_workspace?
      repository_memex_projects_enabled = current_repository.repository_memex_projects_enabled?
      current_repository.owner.organization? ? repository_memex_projects_enabled && current_repository.owner.organization_projects_enabled? : repository_memex_projects_enabled
    end
  end

  memoize def show_classic_projects?
    with_database_error_fallback(fallback: false) do
      return false if repo_is_advisory_workspace?
      current_repository.repository_projects_enabled? && current_repository.has_any_projects? && ProjectsClassicSunset.projects_classic_ui_enabled?(current_user)
    end
  end

  memoize def show_wiki?
    T.bind(self, Repositories::UnderlineNavComponent)
    with_database_error_fallback(fallback: false) do
      current_repository.show_wiki?(current_user, user_can_write_wiki: user_can_write_wiki)
    end
  rescue GitHub::Spokes::ClientError
    false
  end

  memoize def open_issue_count
    return magic_shell.open_repo_issue_count_for_viewer if current_user&.feature_enabled?(:magic_shell_caching)

    with_database_error_fallback(fallback: 0) do
      current_repository.open_issue_count_for(current_user)
    end
  end

  memoize def open_pull_request_count
    with_database_error_fallback(fallback: 0) do
      current_repository.open_pull_request_count_for(current_user)
    end
  end

  memoize def open_project_count
    project_count = open_memex_projects_count

    # Projects classic is currently being sunset.
    # If the user still has projects classic UI enabled, we should include the count of open projects
    project_count += open_classic_project_count if ProjectsClassicSunset.projects_classic_ui_enabled?(current_user, org: current_repository&.organization)

    project_count
  end

  memoize def open_classic_project_count
    if current_user&.feature_enabled?(:magic_shell_caching)
      magic_shell.open_classic_projects_count
    else
      current_repository.projects.open_projects.count
    end
  end

  memoize def can_manage_code_security_settings?
    return false unless logged_in?
    if current_repository.show_config_authzd_enabled?
      current_repository.batched_layout_authzd_permissions(current_user, :can_manage_security_products)
    else
      SecurityProduct::Permissions::RepoAuthz.new(current_repository, actor: current_user).can_manage_security_products?
    end
  end

  private

  memoize def code_tab
    T.bind(self, Repositories::UnderlineNavComponent)
    Site::Header::UnderlineNavTab.new(
      data: { hotkey: "g c" },
      highlight: highlights_for_code,
      href: repository_path(current_repository, current_branch_or_tag_name_for_urls),
      icon: "code",
      text: "Code"
    )
  end

  memoize def issues_tab
    Site::Header::UnderlineNavTab.new(
      count: open_issue_count,
      data: { hotkey: "g i" },
      highlight: highlights_for_issues,
      href: issues_path(current_repository.owner, current_repository),
      voltron_href: issues_index_voltron_path(current_repository.owner, current_repository),
      icon: "issue-opened",
      text: "Issues"
    )
  end

  memoize def pull_requests_tab
    Site::Header::UnderlineNavTab.new(
      count: open_pull_request_count,
      data: { hotkey: "g p" },
      highlight: highlights_for_pulls,
      href: pull_requests_path(current_repository.owner, current_repository),
      icon: "git-pull-request",
      text: "Pull requests",
    )
  end

  memoize def discussions_tab
    Site::Header::UnderlineNavTab.new(
      data: { hotkey: "g g" }.merge(analytics_click_attributes(category: "Discussions", action: "clicked", label: "ref_cta:Discussions;ref_loc:navigation_helper")),
      highlight: highlights_for_discussions,
      href: discussions_path(current_repository.owner, current_repository),
      icon: "comment-discussion",
      text: "Discussions"
    )
  end

  memoize def actions_tab
    Site::Header::UnderlineNavTab.new(
      data: { hotkey: "g a" }.merge(analytics_click_attributes(category: "Actions", action: "clicked", label: "ref_cta:Actions;ref_loc:navigation_helper")),
      highlight: highlights_for_actions,
      href: actions_path(current_repository.owner, current_repository),
      icon: "play",
      text: "Actions"
    )
  end

  memoize def projects_tab
    Site::Header::UnderlineNavTab.new(
      count: open_project_count,
      data: { hotkey: "g b" },
      highlight: highlights_for_projects,
      href: repo_projects_path(current_repository.owner, current_repository),
      icon: "table",
      text: "Projects"
    )
  end

  memoize def wiki_tab
    Site::Header::UnderlineNavTab.new(
      data: { hotkey: "g w" },
      highlight: highlights_for_wiki,
      href: wikis_path(current_repository.owner, current_repository),
      icon: "book",
      text: "Wiki"
    )
  end

  def security_tab(security_counter)
    Site::Header::UnderlineNavTab.new(
      data: { hotkey: "g s" },
      highlight: highlights_for_security,
      href: repository_security_overview_path(current_repository.owner, current_repository),
      icon: "shield",
      text: "Security",
      count: security_counter
    )
  end

  memoize def insights_tab
    Site::Header::UnderlineNavTab.new(
      highlight: highlights_for_graphs,
      href: plan_supports_insights? ? gh_pulse_path(current_repository) : gh_network_dependencies_path(current_repository),
      icon: "graph",
      text: "Insights"
    )
  end

  memoize def settings_tab
    Site::Header::UnderlineNavTab.new(
      highlight: highlights_for_settings,
      href: edit_repository_path(current_repository.owner, current_repository),
      icon: "gear",
      text: "Settings"
    )
  end

  memoize def settings_security_analysis_tab
    Site::Header::UnderlineNavTab.new(
      href: repository_security_and_analysis_path(current_repository.owner, current_repository),
      icon: "gear",
      text: "Settings"
    )
  end

  memoize def custom_tabs
    if GitHub.custom_tabs_enabled? && current_repository.tabs.present?
      current_repository.tabs.map do |tab|
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

  def highlights_for_actions
    [:repo_actions]
  end

  def highlights_for_code
    [:repo_source, :repo_downloads, :repo_commits, :repo_releases, :repo_tags, :repo_branches, :repo_packages, :repo_deployments, :repo_attestations]
  end

  def highlights_for_discussions
    [:repo_discussions]
  end

  def highlights_for_graphs
    [:repo_graphs, :repo_contributors, :dependency_graph, :dependabot_updates, :pulse, :people, :community]
  end

  def highlights_for_issues
    [:repo_issues, :repo_labels, :repo_milestones]
  end

  def highlights_for_projects
    [:repo_projects, :new_repo_project, :repo_project]
  end

  def highlights_for_pulls
    [:repo_pulls, :checks]
  end

  def highlights_for_security
    [:security, :overview, :alerts, :policy, :token_scanning, :code_scanning]
  end

  def highlights_for_settings
    [
      :code_review_limits,
      :codespaces_repository_settings,
      :collaborators,
      :custom_tabs,
      :hooks,
      :integration_installations,
      :interaction_limits,
      :issue_template_editor,
      :key_links_settings,
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
    ]
  end

  def highlights_for_wiki
    [:repo_wiki]
  end

  def open_memex_projects_count
    with_database_error_fallback(fallback: 0) do
      current_repository.open_memex_projects_count_for(current_user)
    end
  end

  memoize def plan_supports_insights?
    current_repository.plan_supports?(:insights)
  end

  def has_repository_permission?(*permissions)
    permissions.include?(current_repository_permission_level)
  end

  memoize def current_repository_permission_level
    current_repository.async_action_or_role_level_for(current_user, include_custom_roles: false).sync
  end
end
