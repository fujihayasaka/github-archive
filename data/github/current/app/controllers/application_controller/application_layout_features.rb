# typed: true
# frozen_string_literal: true

module ApplicationController::ApplicationLayoutFeatures
  APPLICATION_LAYOUT_FEATURES = [
    :custom_search_commands, # site/header/global_search
    :emu_visibility_policy,
    :wikis_visible_by_default,
    :dialog_migration, # enable migrated dialogs
    :tasklist_block, # enable rendering tracking blocks with ```[tasklist] fenced code blocks
    :command_palette, # app/views/layouts/application.html.erb
    :set_slot_returns_nil, # patches an update in ViewComponent for quick revert
    :color_modes_color_blind_themes_2, # replaces existing colorblind themes
    :react_code_search_enabled, # blackbird monolith integration,
    :react_code_view_enabled, # blackbird monolith integration,
    :anonymous_search_and_codeview, # whether to use code view for logged out users
    :secure_user_assets, # rewrites assets urls to use its private version
    :preload_warppipe_flags, # enable preloading feature flags used in warppipe filters
    :glb_ddos_anon_ip_path_limit, # DDoS rate limiter.
    :bulwark_two_factor_required_feature, # enable two factor authentication requirement for bulwark
    :two_factor_holiday_warning_banner, # global flag for 2FA holiday warning banner
    :gists_two_factor_holiday_warning_banner, # global flag for 2FA holiday warning banner in gists
    :scim_rate_limiting_multiplier, # increasing rate limit for SCIM API calls for enterprise accounts
    :tenant_namespacing, # used for loading users via display or unique logins through current tenant
    :reset_tenant_context, # used to force reset the tenant context per request
    :active_job_preserve_tenant_context_method, # whether to use the new method to preserve tenant context in ActiveJob
    :tenant_on_github_v1_request_hydro_event, # tag the github_v1_request event with tenant name + ID in Hydro middleware
    *GitHub::OriginTrials.current_trials.map(&:feature_flag),
    :react_next, # determines if we should load the next version of react bundle
    :rspack, # determines if we should load the rspack bundle
    :alloy_enable_caching, # Enables Alloy caching for an app's request
    :disable_react_ssr, # Disables SSR for user
    :run_split_ability_loader_experiment, # used in all platform::loaders::ability queries
    :split_ability_loader, # used in all platform::loaders::ability queries
    :concurrent_web_requests_limited_route, # used to limit concurrent web requests to mitigate abusive scraping
    :concurrent_web_requests_limited_authenticated, # used to extend limiting to authenticated users
    :concurrent_web_requests_limited_as, # used to limit concurrent web requests to mitigate abusive scraping
    :concurrent_web_requests_limited_max, # used to limit concurrent web requests to mitigate abusive scraping
    :concurrent_web_requests_limited_dry, # used to limit concurrent web requests to mitigate abusive scraping
    :copilot_dotcom_chat,
    :copilot_default_to_task_input, # default copilot button to go to agents view
    :copilot_redirect_header_button_to_agents, # redirect copilot header button to agents view
    :copilot_workspace, # display Copilot Workspace button in issue sidebar
    :copilot_workspace_skip_waitlist, # skip waitlist for Copilot Workspace
    :emu_user_session_expiration, # whether user sessions should have hard expirations based on EMU external identity sessions
    :emu_actions_tab_policy, # whether to disable actions tab for EMUs with disabled self-hosted runners
    :primer_primitives_experimental, # enables some experimental color changes for Primer primitives
    :issues_react_global_add, # whether to enable the new global issue add button in the site header
    :disable_issues_service_worker, # kill switch for the issues service worker
    :marketing_cookie_consent_banner, # enables cookie consent management
    :dashboard_jan_2026_privacy_copilot_nudge, # in-product targeting nudge
    :in_product_messaging_transactional_message_engine, # transactional in-product messages
    :ipm_global_transactional_message_org, # transactional in-product messages for org pages
    :ipm_global_transactional_message_enterprise, # transactional in-product messages for enterprise pages
    :mona_sans, # enables mona sans font for users who have it locally installed
    :monaspace_font, # enables monaspace font for users who have it locally installed
    :emu_policies_helper_ability_delegate, # enables ability delegate for emu policies helper
    :rev_parse_git, # enables a Git-based implementation for the rev_parse Gitrpc endpoint
    :dashboard_nav_experiment, # related to this UI experiment: https://github.com/github/github/pull/372845
    :global_nav_react, # enables the React version of the global top-nav (including left-nav and the user-menu)
    :global_nav_dual_emit_tab_metrics, # enables dual emission of tab generation timing metrics for the global nav
    :global_nav_react_blackbird_fragment, # enables the React version of the global nav blackbird search fragment
    :global_nav_exclude_project_count, # excludes project count from repo global nav
    :global_nav_security_count_cache, # enables caching for security count in repo global nav
    :optimized_org_counts, # enables a 5,001 count limit on organization profile tab counts
    :configsd_entries_experiment, # configsd experiment for Configuration Entries
    :batched_configsd_entries_experiment, # batched configsd experiment for Configuration Entries
    :enterprise_access_header_verification_login, # enables a check for the business header passed in as part of the request, valid for EMUs only
    :primer_button_break_line, # allow primer beta button label text to break line
    :primer_deprecate_input_contrast_mode, # enables deprecation of input contrast mode in Primer
    :primer_react_segmented_control_tooltip, # enables tooltip on SegmentedControl.IconButton
    :disable_mathjax, # functions as a long-lived emergency shutoff in case of MathJax incidents
    :actionable_two_factor_security_checkup, # enables the actionable two factor security checkup global banners
    :throttle_expensive_gitrpc_calls, # enables throttling for expensive gitrpc calls
    :belongs_to_repo_domain, # load Model#repository through domain interface
    :owner_context_propagation, # gates owner context propagation for shard boundary detection
    :projects_classic_sunset_override, # a support/staff-only flag to allow overriding the Projects (classic) sunset in the rare situation we need to still allow it to be accessible.
    :log_applicable_external_conditional_access_policy, # logs the applicability of external conditional access policy
    :private_avatars, # enables jwt signed private avatars
    :proxima_avatar_tenant_slug_fix,
    :via_domain_singleton,
    :rate_limit_early, # safe rollout of moving rate limiting earlier in the request lifecycle
    :actor_id_result_batching, # enables actor id result batching for the actor ids query
    :site_turbo_disable, # Turbo disable for marketing pages
    :session_cookie_analysis, # temporary logging during session authentication
    :override_fetch, # overrides the fetch function to always add the X-Requested-With header
    :copilot_chat_dashboard_entrypoint, # use the immersive entrypoint for copilot chat on the dashboard,
    :copilot_spaces_enterprise_opt_out, # temp flag to disable copilot spaces for an enterprise
    :copilot_spaces_enterprise_user_opt_in, # enable copilot spaces for specific users no matter what
    :kb_semantic_api_migration, # enables the migration of the knowledge base semantic API
    :copilot_free_limited_user, # enables copilot free user experience
    :copilot_premium_request_quotas, # enables copilot premium request quota tracking in the UI
    :sdn_copilot_vnext, # enables the new Copilot trade controls SDN treatment
    :report_authzd_indeterminates, # enabled error reporting for authzd indeterminate responses
    :run_authzd_cap_experiment, # enables the authzd cap experiment
    :authzd_cap_experiment_actor_participation_rate, # sets participation rate for actors opted into cap experimentation
    :run_authzd_cap_experiment_for_actor, # used to run cap experiments at a higher frequency for selected actors
    :run_authzd_cap_experiment_web, # enables the authzd cap experiment for web enforcer
    :run_authzd_cap_filter_experiment, # enables the authzd cap filter experiment
    :run_authzd_cap_filter_experiment_view, # enables the authzd cap filter experiment for view filter
    :user_session_authzd_cap_production,
    :user_session_authzd_cap_experiment,
    :use_authzd_mesh_client, # use the authzd mesh client for authzd requests
    :use_authzd_mesh_enumerator_client, # use the authzd mesh enumerator_client for authzd requests
    :skip_authzd_cap_in_test, # test only, 2 of 2 flags for explicit test opt-in to use authzd cap
    :skip_authzd_cap_access_allowed_for_businesses, # disables authzd cap access for businesses
    :skip_authzd_cap_for_biz_team_preview, # disables authzd cap access for biz team preview
    :use_authzd_cap_filter_global, # enables the authzd cap filter for all users
    :use_authzd_cap_global, # global killswitch for using authzd CAP or not
    :use_authzd_cap_global_git_auth, # killswitch for authzd CAP in the git_auth enforcer
    :use_authzd_cap_global_api, # killswitch for authzd CAP in the the api enforcer
    :use_authzd_cap_global_web, # killswitch for authzd CAP in the the web enforcer
    :use_authzd_cap_global_internal_api, # killswitch for authzd CAP in the the internal_api enforcer
    :use_authzd_cap_darkship_git_auth, # darkship enablement for authzd CAP in the the git_auth enforcer
    :use_authzd_cap_darkship_api, # darkship enablement for authzd CAP in the the api enforcer
    :use_authzd_cap_darkship_web, # darkship enablement for authzd CAP in the the web enforcer
    :use_authzd_cap_darkship_internal_api, # darkship enablement for authzd CAP in the the internal_api enforcer
    :use_authzd_cap_emu_git_auth, # EMU actor based enablement for authzd CAP in the the git_auth enforcer
    :use_authzd_cap_emu_api, # EMU actor based enablement for authzd CAP in the the api enforcer
    :use_authzd_cap_emu_web, # EMU actor based enablement for authzd CAP in the the web enforcer
    :use_authzd_cap_emu_internal_api, # EMU actor based enablement for authzd CAP in the the internal_api enforcer
    :use_authzd_cap_non_emu_git_auth, #enablement for authzd CAP in the the git_auth enforcer targeting non-emu actors
    :use_authzd_cap_non_emu_api, #enablement for authzd CAP in the the api enforcer targeting non-emu actors
    :use_authzd_cap_non_emu_web, #enablement for authzd CAP in the the web enforcer targeting non-emu actors
    :use_authzd_cap_non_emu_internal_api, #enablement for authzd CAP in the the internal_api enforcer targeting non-emu actors
    :external_cap_use_real_actor, # fix bug in external cap policy where u2s tokens are inapplicable
    :skip_authzd_ctrl_access_in_test, # To disable/opt-out of authzd's control access service in tests
    :use_authzd_ctrl_access_global, # For use of authzd's control access service
    :batch_business_org_abilities, # batch calls to abilities for orgs in a business
    :run_business_org_abilities_experiment, # enable running the experiment to batch calls to abilities for orgs in a business
    :remote_cache, # enables remote cache for all caching usages
    :remote_cache_redis_ping, # enables pinging the remote cache redis store before using it
    :remote_cache_redis_ping_connected, # ping the remote cache redis store unless connected
    :endpoint_anon_blocked_actors, # feature flag used for blocking anonymous requests for specific endpoints based on IP address, JA3 hash, JA4 fingerprint, and JA4H fingerprint
    :dotcom_web_blocked_ip_addresses, # feature flag used for blocking requests from certain IP addresses via GLB abuse blocking
    :dotcom_web_ip_addresses_blocking, # whether the blocking above is fully enabled or running in dry run mode
    :authzd_test_flag, # CI only FF needed until Vexi interprocess flag syncing is enabled
    :navbar_counter_caching_pull_requests_count, # enables caching of PR counts in the navbar
    :navbar_counter_caching_pull_requests_count_shadow, # disables shadow mode for PR counts caching in the navbar
    :navbar_counter_caching_pull_requests_count_invalidation, # enables invalidation of PR counts in the navbar
    :navbar_counter_caching_project_count, # enables caching of project counts in the navbar
    :navbar_counter_caching_project_count_ttl, # TTL for project count caching
    :navbar_counter_caching_project_count_shadow, # disables shadow mode for project count caching in the navbar
    :remote_cache_repo_route, # experiment caching current_repository by route
    :remote_cache_configs_ttl, # TTL for configuration entries
    :remote_cache_configs_single_enabled, # enables caching of configuration entries
    :remote_cache_configs_single_shadow_mode, # enables shadow mode for config entries caching
    :remote_cache_configs_batch_enabled,
    :remote_cache_configs_batch_shadow_mode,
    :remote_cache_configs_invalidate, # enables invalidation of config entries caching
    :copilot_workbench, # show/hide Spark (known as `copilot_workbench`)
    :github_spark, # show/hide GitHub Spark (additional flag for waitlisted users)
    :coding_agent_add_menu_link, # show/hide "New agent task" in the global add menu
    :ui_manifest_warmup, # allow a special "warmup" target to asynchronously pre-load ui manifest during requests
    :ui_manifest_sha_mysql_first, # read ui sha from mysql before ui-deploys
    :disable_ui_deploys_manifest, # disable fetching ui manifests from ui-deploys
    :disable_ui_deploys_sha, # disable fetching ui shas from ui-deploys
    :primer_react_select_panel_fullscreen_on_narrow, #  allows for the SelectPanel to go full-screen on narrow viewports
    :spokesd_use_httpv11, # switches one spokesd client from H2 to HTTP/1.1
    :bypass_pat_lifetime_policies_check, # bypasses the check for PAT lifetime policies
    :disable_legacy_es_cluster_metric,  # disables emitting the `es_cluster` dd tag in lieu of the new `search_cluster` tag
    :redirect_invalid_sessions, # dry-run flag for redirecting web requests with invalid user_session cookies
    :redirect_invalid_sessions_enforcement, # enforcement flag for redirecting web requests with invalid user_session cookie
    :issues_erb_template_render_tracking, # enables tracking of ERB template rendering in issues
    :use_javascript_modules, # enables the "module" type for all JavaScript script tag bundles
    :token_scanning_use_staging, # enables token scanning to use staging environment for existing assessment check (needed for rendering Organization#scan_secret_leaks_banner)
    :authzd_biz_has_all_repo_read, # enables Authzd to handle all repo read for biz teams
    :authzd_biz_has_all_repo_read_science_only, # enables Authzd to run an all repo read for science traffic only
    :authzd_biz_teams_repo_readable_by, # enables authzd to check if biz teams can read a repo
    :authzd_biz_teams_repo_readable_by_science_only, # enables authzd to check if biz teams can read a repo for science traffic only
    :vitess_append_max_execution_time_comment_issues_pull_requests, # appends MAX_EXECUTION_TIME optimizer hint to relevant queries
    :vitess_use_new_max_execution_time_issues_pull_requests, # appends MAX_EXECUTION_TIME optimizer hint to relevant queries, using the new timeout value
    :vitess_append_max_execution_time_comment_billing, # appends MAX_EXECUTION_TIME optimizer hint to relevant queries
    :vitess_use_new_max_execution_time_billing, # appends MAX_EXECUTION_TIME optimizer hint to relevant queries, using the new timeout value
    :vitess_append_max_execution_time_comment_notifications_entries, # appends MAX_EXECUTION_TIME optimizer hint to relevant queries
    :vitess_use_new_max_execution_time_notifications_entries, # appends MAX_EXECUTION_TIME optimizer hint to relevant queries, using the new timeout value
    :vitess_append_max_execution_time_comment_pages, # appends MAX_EXECUTION_TIME optimizer hint to relevant queries
    :vitess_use_new_max_execution_time_pages, # appends MAX_EXECUTION_TIME optimizer hint to relevant queries, using the new timeout value
    :vitess_append_max_execution_time_comment_permissions, # appends MAX_EXECUTION_TIME optimizer hint to relevant queries
    :vitess_use_new_max_execution_time_permissions, # appends MAX_EXECUTION_TIME optimizer hint to relevant queries, using the new timeout value
    :vitess_append_max_execution_time_comment_repositories_actions_checks, # appends MAX_EXECUTION_TIME optimizer hint to relevant queries
    :vitess_use_new_max_execution_time_repositories_actions_checks, # appends MAX_EXECUTION_TIME optimizer hint to relevant queries, using the new timeout value
    :vitess_append_max_execution_time_comment_repositories_pushes_sharded, # appends MAX_EXECUTION_TIME optimizer hint to relevant queries
    :vitess_use_new_max_execution_time_repositories_pushes_sharded, # appends MAX_EXECUTION_TIME optimizer hint to relevant queries, using the new timeout value
    :vitess_append_max_execution_time_comment_token_scanning_service_prod, # appends MAX_EXECUTION_TIME optimizer hint to relevant queries
    :vitess_use_new_max_execution_time_token_scanning_service_prod, # appends MAX_EXECUTION_TIME optimizer hint to relevant queries, using the new timeout value
    :vitess_append_max_execution_time_comment_lodge, # appends MAX_EXECUTION_TIME optimizer hint to relevant queries
    :vitess_use_new_max_execution_time_lodge, # appends MAX_EXECUTION_TIME optimizer hint to relevant queries, using the new timeout value
    :codespaces_proxima_enablement, # enables codespaces on proxima
    :copilot_global_agent_button, # enables the dedicated global agent panel button in the site header
    :copilot_global_agent_button_popover, # enables the dedicated global agent panel button popover
    :copilot_global_agent_button_popover_ignore_dismiss, # enables the dedicated global agent panel button popover but ignores dismissing for testing
    :copilot_free_user_popover_ignore_dismiss, # enables the dedicated global agent panel button popover for free users, but ignores dismissing for testing
    :repos_relevance_page, # enables the repos relevance icons on the header and global sidebar
    :copilot_sku_isolation_use_public_user, # dynamically calculates Copilot URLs based on the user's SKU
    :copilot_sku_isolation_use_public_user_perf, # uses cached public user for calculating Copilot URL
    :coding_agent_in_proxima, # enables Copilot coding agent usage in Proxima
    :cache_authzd_not_applicable, # enables caching of not applicable authzd decisions
    :primer_live_region_element,
    :react_quality_profiling,
    :speculation_rules, # enables the Speculation Rules API to preload resources
    :respect_absolute_time_preference, # enables display of absolute time formats based on user preference
    :rate_limited_request_anon_ip_allowlist, # allowlist for anonymous IPs to bypass controller specific request rate limiting
    :ip_and_path_limiter_anon_ip_allowlist, # enables allowlisting of anonymous requests by IP address to bypass CountAnonymousByIPAndPath rate limiter
    :copilot_mission_control_link_to_sessions_in_repo, # link to repo agents view for agent tasks
    :copilot_mission_control_link_to_hyperspace, # link to hyperspace task view for agent tasks
    :primer_tailwind_compatible, # loads a smaller tailwindcss-compatible bundle instead of the full bundle
    :primer_tailwind_utilities, # loads the tailwind utilities css bundle
    :behaviors_lazy_define, # loads behaviors-lazy.js bundle instead of behaviors.js
  ].flatten.to_set.freeze
end
