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

    if show_projects?
      tabs << projects_tab
    end

    if show_models?
      tabs << models_tab
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
      if current_user&.feature_enabled?(:magic_shell_caching)
        magic_shell.repo_should_display_actions?
      else
        current_repository.show_actions?
      end
    end
  end

  memoize def repo_is_advisory_workspace?
    return false unless GitHub.repository_advisories_enabled?
    if current_user&.feature_enabled?(:magic_shell_caching)
      magic_shell.repo_is_advisory_workspace?
    else
      current_repository.advisory_workspace?
    end
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
      open_issue_count
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

  memoize def show_models?
    return false unless GitHub.models_enabled?
    is_feature_enabled = current_user&.feature_enabled?(:github_models_repo_tab) ||
      GitHub.flipper[:github_models_repo_tab].enabled?
    return false unless is_feature_enabled

    true
  end

  memoize def show_wiki?
    T.bind(self, Repositories::UnderlineNavComponent)
    with_database_error_fallback(fallback: false) do
      current_repository.show_wiki?(current_user, user_can_write_wiki: user_can_write_wiki)
    end
  rescue GitHub::Spokes::ClientError
    false
  end

  # For now, we're restricting cache usage to a specific case of possible execution
  # paths. This specific case is luckily the common case:
  #   - the repo is not spammy, AND
  #   - the viewer is not the owner of the repo or a site admin, AND
  #   - the viewer is not logged in or is logged in and not spammy
  # In that case, the generated SQL query depends only on the repository ID, and not the viewer's ID.
  # So, we can cache the counter and use it for most anonymous and authenticated viewers of that repo.
  def use_navbar_cache?(viewer, repository)
    logged_in = !viewer.nil?
    site_admin = viewer&.site_admin?
    viewer_spammy = viewer&.spammy?
    repo_spammy = repository&.spammy?
    viewer_owner = viewer&.id == repository&.owner_id

    return false if repo_spammy   # dont use cache if repo is spammy
    return false if viewer_owner  # show fresh values to repo owners
    return false if site_admin    # show fresh values to site admins

    return true  if !logged_in || !viewer_spammy

    false
  end

  # Determine the TTL for caching the value based on the value itself. The idea is to take
  # advantage of how we display counters depending on the value of the counter. Values under
  # 1000 get displayed in full precision, values between 1000 and 5000 get rounded to the
  # closest 100, and values over 5000 are displayed as 5k+. With that in mind, we can cache
  # values over 5000 with a longer TTL since small changes in the number of open issues won't
  # affect the displayed counter. For values under 5000 and above 1000, we use a shorter TTL
  # since fewer changes are required to change the displayed value. For values under
  #
  # The extra 100 in 5100 and 1100 is a buffer to make sure we're well above the lower bounds
  # and don't slip into the lower segment on minor changes to the value. E.g. imagine if there
  # were 1002 open issues, and four issues are closed so there are now 998 open issues.
  #
  # The TTLs for the different segments are defined by feature flags, one for each segment. The
  # percentage_of_actors_value for the flag multiplied by 100 represents the TTL in seconds. The
  # minimum value for the flag is 0, and the smallest increment supported by feature flags is 0.01,
  # which allows us to change the TTL from 0 to 10000 seconds (=166.66 minutes) in increments of
  # 1 second. Here are a few examples:
  #
  # 0.00%  => 0.00 * 100  => 0 seconds
  # 0.01%  => 0.01 * 100  => 1 second
  # 1.00%  => 1.00 * 100  => 100 seconds
  # 32.65% => 32.65 * 100 => 3265 seconds
  def counter_caching_ttl(value)
    feature_flag = case value
    when 5100..Float::INFINITY
      :navbar_counter_caching_ttl_over5k
    when 1100..5099
      :navbar_counter_caching_ttl_over1k
    else
      :navbar_counter_caching_ttl_under1k
    end

    GitHub.flipper[feature_flag].percentage_of_actors_value * 100
  end

  # Construct the cache key based on parts. The key is basically the strong join of the parts
  # with a "repo_navbar" prefix as a namespace. For example, if these are the parts passed in:
  #
  #   ["open_issue_count", "viewer_anon_or_not_spammy", "repo_id:123"]
  #
  # then the constructed cache key will be:
  #
  #   "repo_navbar-open_issue_count-viewer_anon_or_not_spammy-repo_id:123"
  def counter_cache_key(parts)
    parts.prepend("repo_navbar").join("-")
  end

  # All the feature flags that need to be enabled in order to use caching.
  def caching_feature_flags_enabled?(viewer, repository)
    # The "navbar_counter_caching" feature flag controlls for which repositories should use the
    # cache. This flag will not initially be rolled out using %, but rather by enabling the flag
    # for a small set of repositories so that we can monitor the metrics for those specific
    # repositories. The "navbar_hits" and "navbar_hits_details" feature flags are for enabling
    # telemetry, and we check those as well since we don't want to use caching if the associated
    # telemetry is not enabled.
    GitHub.flipper[:navbar_counter_caching].enabled?(repository) &&
    GitHub.flipper[:navbar_hits].enabled?(viewer) &&
    GitHub.flipper[:navbar_hits_details].enabled?(repository)
  end

  def caching_group_tag(value)
    case value
    when 5100..Float::INFINITY
      "caching_group:over5k"
    when 1100..5099
      "caching_group:over1k"
    else
      "caching_group:under1k"
    end
  end

  # TODO metrics to help us determine how often we're showing stale data
  memoize def open_issue_count
    return magic_shell.open_repo_issue_count_for_viewer if current_user&.feature_enabled?(:magic_shell_caching)

    # We will use the cache if: a) all the feature flags are enabled, and b) the execution path
    # is the one we support for caching. Otherwise, we skip the cache and use only the database.
    navbar_counter_caching_enabled = caching_feature_flags_enabled?(current_user, current_repository)
    execution_path_supports_cache = use_navbar_cache?(current_user, current_repository)

    if !navbar_counter_caching_enabled || !execution_path_supports_cache
      # If we're not using caching, then collect metrics for the old approach which uses only the database
      with_navbar_hits("github.nav_bar.issue_count") do |metric_tags = []|
        metric_tags.push(navbar_counter_caching_enabled ? "navbar_cache_enabled:true" : "navbar_cache_enabled:false")
        metric_tags.push(execution_path_supports_cache ? "cache_supported_case:true" : "cache_supported_case:false")

        with_database_error_fallback(fallback: 0) do
          current_repository.open_issue_count_for(current_user)
        end
      end
    else
      with_navbar_hits("github.nav_bar.issue_count") do |metric_tags = []|
        metric_tags.push("navbar_cache_enabled:true", "cache_supported_case:true")

        # Construct the cache key
        cache_key = counter_cache_key(["open_issue_count", "viewer-anon-or-not-spammy", "repo_id:#{current_repository.id}"])

        # Fetch value from cache
        cached_value = GitHub.cache.get(cache_key)

        # Return value if it was found in cache
        if !cached_value.nil?
          metric_tags.push("cache_hit:true", caching_group_tag(cached_value))
          next cached_value
        end

        # If the value was not found in cache, fetch it from the database with graceful degradation to 0.
        db_value = with_database_error_fallback(fallback: 0) do
          current_repository.open_issue_count_for(current_user, limit: 5100)
        end

        metric_tags.push("cache_hit:false", caching_group_tag(db_value))

        # Determine TTL for this value and cache the value for that amount of seconds
        if (ttl = counter_caching_ttl(db_value)) && ttl.is_a?(Numeric) && ttl > 0
          GitHub.cache.set(cache_key, db_value, ttl.to_i.seconds)
        end

        # Return the value obtained from the database
        db_value
      end
    end
  end

  memoize def open_pull_request_count
    with_navbar_hits("github.nav_bar.pr_count") do
      with_database_error_fallback(fallback: 0) do
        current_repository.open_pull_request_count_for(current_user)
      end
    end
  end

  memoize def open_project_count
    open_memex_projects_count
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

  memoize def models_tab
    Site::Header::UnderlineNavTab.new(
      data: { hotkey: "g m" },
      highlight: highlights_for_models,
      href: repo_models_path(current_repository.owner, current_repository),
      icon: "ai-model",
      text: "Models"
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

  def highlights_for_models
    [:repo_models, :repo_models_prompts]
  end

  def highlights_for_wiki
    [:repo_wiki]
  end

  def open_memex_projects_count
    with_navbar_hits("github.nav_bar.proj_count") do
      with_database_error_fallback(fallback: 0) do
        current_repository.open_memex_projects_count_for(current_user)
      end
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

  def with_navbar_hits(stat)
    return yield unless GitHub.flipper[:navbar_hits].enabled?(current_user)

    logged_in_tag = !!current_user ? "logged_in:true" : "logged_in:false"
    site_admin_tag = current_user&.site_admin? ? "viewer_site_admin:true" : "viewer_site_admin:false"
    viewer_spammy_tag = current_user&.spammy? ? "viewer_spammy:true" : "viewer_spammy:false"
    repo_spammy_tag = current_repository&.spammy? ? "repo_spammy:true" : "repo_spammy:false"
    viewer_owner_tag = current_user&.id == current_repository&.owner_id ? "viewer_owner:true" : "viewer_owner:false"

    metric_tags = [logged_in_tag, site_admin_tag, viewer_spammy_tag, repo_spammy_tag, viewer_owner_tag]
    extra_tags = []

    if current_repository && GitHub.flipper[:navbar_hits_details].enabled?(current_repository)
      metric_tags << "repo_id:#{current_repository.id}"
    end

    begin
      mysql_queries_start = GitHub::MysqlInstrumenter.query_count
      mysql_time_start = GitHub::MysqlInstrumenter.query_time
      memcached_queries_start = Memcached::Rails.query_count
      memcached_time_start = Memcached::Rails.query_time
      redis_queries_start = ::Redis::Client.query_count
      redis_time_start = ::Redis::Client.query_time

      timer = ::Timer.start
      yield(extra_tags)
    ensure
      timer.stop
      metric_tags.concat(extra_tags)

      mysql_queries = GitHub::MysqlInstrumenter.query_count - mysql_queries_start
      mysql_time = GitHub::MysqlInstrumenter.query_time - mysql_time_start
      memcached_queries = Memcached::Rails.query_count - memcached_queries_start
      memcached_time = Memcached::Rails.query_time - memcached_time_start
      redis_queries = ::Redis::Client.query_count - redis_queries_start
      redis_time = ::Redis::Client.query_time - redis_time_start

      GitHub.dogstats.distribution("#{stat}.time", timer.elapsed_ms(5), tags: metric_tags)
      GitHub.dogstats.distribution("#{stat}.cpu_time", timer.elapsed_cpu_ms(5), tags: metric_tags)
      GitHub.dogstats.distribution("#{stat}.cpu_thread_time", timer.elapsed_thread_cpu_ms(5), tags: metric_tags)
      GitHub.dogstats.distribution("#{stat}.idle_time", timer.elapsed_idle_ms(5), tags: metric_tags)

      GitHub.dogstats.distribution("#{stat}.mysql_queries", mysql_queries, tags: metric_tags)
      GitHub.dogstats.distribution("#{stat}.mysql_time", mysql_time, tags: metric_tags)
      GitHub.dogstats.distribution("#{stat}.memcached_queries", memcached_queries, tags: metric_tags)
      GitHub.dogstats.distribution("#{stat}.memcached_time", memcached_time, tags: metric_tags)
      GitHub.dogstats.distribution("#{stat}.redis_queries", redis_queries, tags: metric_tags)
      GitHub.dogstats.distribution("#{stat}.redis_time", redis_time, tags: metric_tags)
    end
  end
end
