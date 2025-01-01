# typed: true
# frozen_string_literal: true

module ApplicationController::ApplicationLayoutFeatures
  APPLICATION_LAYOUT_FEATURES = [
    :custom_search_commands, # site/header/global_search
    :emu_visibility_policy,
    :memex_insights,
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
    :pwa, # Progressive Web App experiment, adds an offline page
    :react_next, # determines if we should load the next version of react bundle
    :alloy_enable_caching, # Enables Alloy caching for an app's request
    :disable_react_ssr, # Disables SSR for user
    :notifications_indicator_async_fetch, # determines if we should fetch the notifications icon status asynchronously
    :run_split_ability_loader_experiment, # used in all platform::loaders::ability queries
    :split_ability_loader, # used in all platform::loaders::ability queries
    :concurrent_web_requests_limited_route, # used to limit concurrent web requests to mitigate abusive scraping
    :concurrent_web_requests_limited_authenticated, # used to extend limiting to authenticated users
    :concurrent_web_requests_limited_as, # used to limit concurrent web requests to mitigate abusive scraping
    :concurrent_web_requests_limited_max, # used to limit concurrent web requests to mitigate abusive scraping
    :concurrent_web_requests_limited_dry, # used to limit concurrent web requests to mitigate abusive scraping
    :copilot_dotcom_chat,
    :copilot_chat_rails_anchor, # use a rails rendered anchor to trigger copilot chat experience
    :copilot_f2p, # add free to paid UI changes for copilot
    :copilot_workspace, # display Copilot Workspace button in issue sidebar
    :copilot_workspace_skip_waitlist, # skip waitlist for Copilot Workspace
    :emu_user_session_expiration, # whether user sessions should have hard expirations based on EMU external identity sessions
    :emu_actions_tab_policy, # whether to disable actions tab for EMUs with disabled self-hosted runners
    :primer_primitives_experimental, # enables some experimental color changes for Primer primitives
    :contribution_graph_borders_override, # enables the contribution graph borders override
    :issues_react_global_add, # whether to enable the new global issue add button in the site header
    :marketing_cookie_consent_banner, # enables cookie consent management
    :mona_sans, # enables mona sans font for users who have it locally installed
    :monaspace_font, # enables monaspace font for users who have it locally installed
    :emu_policies_helper_ability_delegate, # enables ability delegate for emu policies helper
    :rev_parse_git, # enables a Git-based implementation for the rev_parse Gitrpc endpoint
    :eager_load_global_nav, # Removes placeholders in global nav and eager loads content
    :react_global_create_menu, # Render the React version of the Create Menu in the Global Nav
    :global_nav_experiment, # related to this UI experiment: https://github.com/github/github/pull/372845
    :dashboard_nav_experiment, # related to this UI experiment: https://github.com/github/github/pull/372845
    :log_missing_global_navigation_crumbs, # logs missing global navigation crumbs to Datadog
    :global_nav_request_check, # enables additional request type checks for global nav breadcrumbs
    :global_nav_react_menu, # enables the React version of the global left-nav
    :global_nav_copilot_a11y_fix, # enables a fix for the Copilot menu not being accessible on small viewports
    :enterprise_access_header_verification_login, # enables a check for the business header passed in as part of the request, valid for EMUs only
    :primer_button_break_line, # allow primer beta button label text to break line
    :primer_deprecate_input_contrast_mode, # enables deprecation of input contrast mode in Primer
    :primer_react_action_list_item_as_button, # enables using buttons in action list items in Primer React
    :primer_react_overlay_overflow, # enables responsive overlay with width overflows
    :primer_react_segmented_control_tooltip, # enables tooltip on SegmentedControl.IconButton
    :disable_mathjax, # functions as a long-lived emergency shutoff in case of MathJax incidents
    :global_notice_domain, # enables the new global notice domain
    :actionable_two_factor_security_checkup, # enables the actionable two factor security checkup global banners
    :throttle_expensive_gitrpc_calls, # enables throttling for expensive gitrpc calls
    :magic_shell_caching, # powering layout caching
    :belongs_to_repo_domain, # load Model#repository through domain interface
    :projects_classic_sunset_override, # a support/staff-only flag to allow overriding the Projects (classic) sunset in the rare situation we need to still allow it to be accessible.
    :log_applicable_external_conditional_access_policy, # logs the applicability of external conditional access policy
    :private_avatars, # enables jwt signed private avatars
    :proxima_avatar_tenant_slug_fix,
    :via_domain_singleton,
    :rate_limit_early, # safe rollout of moving rate limiting earlier in the request lifecycle
    :actor_id_result_batching, # enables actor id result batching for the actor ids query
    :cap_filter_consider_outside_collabs, # allows conditional access policies to be able to filter content for outside collaborators
    :cap_retry_instrumentation, # add datadog metrics for authzd cap retries
    :site_turbo_disable, # Turbo disable for marketing pages
    :react_app_dvh, # uses dvh instead of vh for .react-app height calculation
    :session_cookie_analysis, # temporary logging during session authentication
    :disable_global_anonymous_search_count, # disables a very conservative global rate limit for anon search requests
    :override_fetch, # overrides the fetch function to always add the X-Requested-With header
    :copilot_chat_dashboard_entrypoint, # use the immersive entrypoint for copilot chat on the dashboard,
    :bundles_keep_css_modules, # used in the bundle helper to fix css modules being removed by react partial re-renders
    :copilot_custom_copilots, # enables the ability to have custom copilots
    :copilot_custom_copilots_feature_preview, # temp flag to enable custom copilots in beta features
    :kb_semantic_api_migration, # enables the migration of the knowledge base semantic API
    :copilot_free_limited_user, # enables copilot free user experience
    :copilot_premium_request_quotas, # enables copilot premium request quota tracking in the UI
    :sdn_copilot_vnext, # enables the new Copilot trade controls SDN treatment
    :report_authzd_indeterminates, # enabled error reporting for authzd indeterminate responses
    :run_authzd_cap_experiment, # enables the authzd cap experiment
    :authzd_cap_experiment_actor_participation_rate, # sets participation rate for actors opted into cap experimentation
    :authzd_cap_experiment_tfca_participation_rate, # sets participation rate for TFCAs opted into cap experimentation
    :run_authzd_cap_experiment_for_actor, # used to run cap experiments at a higher frequency for selected actors
    :run_authzd_cap_experiment_for_tfca, # used to run cap experiments at a higher frequency for selected TFCAs
    :run_authzd_cap_experiment_web, # enables the authzd cap experiment for web enforcer
    :run_authzd_cap_filter_experiment, # enables the authzd cap filter experiment
    :run_authzd_cap_filter_experiment_view, # enables the authzd cap filter experiment for view filter
    :use_authzd_mesh_client, # use the authzd mesh client for authzd requests
    :use_authzd_mesh_enumerator_client, # use the authzd mesh enumerator_client for authzd requests
    :use_authzd_mesh_controlaccess_client, # use the authzd mesh controlaccess_client for authzd requests
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
    :skip_authzd_ctrl_access_in_test, # To disable/opt-out of authzd's control access service in tests
    :use_authzd_ctrl_access_global, # For use of authzd's control access service
    :use_authzd_ctrl_access_s2s_requests, # Authzd control access service enablement for server-to-server request tokens
    :use_authzd_ctrl_access_u2s_requests, # Authzd control access service enablement for user-to-server request tokens
    :use_authzd_ctrl_access_gloabl_u2s_requests, # Authzd control access service enablement for user-to-server request tokens
    :use_authzd_ctrl_access_programmatic_requests, # Authzd control access service enablement for user-with-programmatic-access request tokens
    :use_authzd_ctrl_access_scoped_user_requests, # Authzd control access service enablement for user-with-scopes request tokens
    :use_authzd_ctrl_access_null_requests, # Authzd control access service enablement for null request tokens
    :batch_business_org_abilities, # batch calls to abilities for orgs in a business
    :run_business_org_abilities_experiment, # enable running the experiment to batch calls to abilities for orgs in a business
    :open_issue_count_caching, # enables caching of open issue count for specific repositories
    :open_issue_count_caching_invalidation, # enables invalidation of open issue count cache for specific repositories
    :open_issue_count_caching_disable_shadow_mode, # disables shadow mode for issue count caching
    :remote_cache, # enables remote cache for all caching usages
    :remote_cache_redis_ping, # enables pinging the remote cache redis store before using it
    :remote_cache_redis_ping_connected, # ping the remote cache redis store unless connected
    :endpoint_anon_blocked_actors, # feature flag used for blocking anonymous requests for specific endpoints based on IP address or JA3 hash
    :dotcom_web_blocked_ip_addresses, # feature flag used for blocking requests from certain IP addresses via GLB abuse blocking
    :dotcom_web_ip_addresses_blocking, # whether the blocking above is fully enabled or running in dry run mode
    :case_insensitive_label_ordering_gql, # Use case insensitive search in the labels field for issues
    :authzd_test_flag, # CI only FF needed until Vexi interprocess flag syncing is enabled
    :navbar_counter_caching_pull_requests_count, # enables caching of PR counts in the navbar
    :navbar_counter_caching_pull_requests_count_shadow, # disables shadow mode for PR counts caching in the navbar
    :navbar_counter_caching_pull_requests_count_invalidation, # enables invalidation of PR counts in the navbar
    :navbar_counter_caching_project_count, # enables caching of project counts in the navbar
    :navbar_counter_caching_project_count_ttl, # TTL for project count caching
    :navbar_counter_caching_project_count_shadow, # disables shadow mode for project count caching in the navbar
    :remote_cache_circuit_breaker, # enables circuit breaker for remote cache via redis client
    :remote_cache_circuit_breaker_error_threshold, # error threshold for circuit breaker
    :remote_cache_circuit_breaker_error_threshold_timeout, # timeout for error threshold
    :remote_cache_circuit_breaker_error_timeout, # error timeout for circuit breaker
    :remote_cache_circuit_breaker_success_threshold, # success threshold for circuit breaker
    :remote_cache_app_worker_id_tag, # adds app worker ID to remote cache metrics as a tag
    :remote_cache_redis_client_object_id_tag, # adds redis client object ID to remote cache metrics as a tag
    :remote_cache_repo_route, # experiment caching current_repository by route
    :remote_cache_repo_shadow, # shadow mode for repo caching
    :copilot_workbench, # show/hide Spark (known as `copilot_workbench`)
    :github_spark, # show/hide GitHub Spark (additional flag for waitlisted users)
    :coding_agent_add_menu_link, # show/hide "New agent task" in the global add menu
    :enterprise_teams_attributes_include_business_teams, # include business teams in authzd team attributes
    :report_ui_target, # report the UI target to Datadog
    :ui_manifest_warmup, # allow a special "warmup" target to asynchronously pre-load ui manifest during requests
    :ui_manifest_sha_redis_first, # read ui sha from redis before mysql
    :client_version_header, # enables the client version header for fetch requests
    :fetch_nonce_block, # enables blocking requests with mismatched fetch nonces
    :primer_react_select_panel_fullscreen_on_narrow, #  allows for the SelectPanel to go full-screen on narrow viewports
    :spokesd_use_httpv11, # switches one spokesd client from H2 to HTTP/1.1
    :bypass_pat_lifetime_policies_check, # bypasses the check for PAT lifetime policies
    :ip_allowlist_org_apps_access_business_target, # IP allowlist CAP - installation is on an organization, the Business has IP allowlist configured
    :disable_legacy_es_cluster_metric,  # disables emitting the `es_cluster` dd tag in lieu of the new `search_cluster` tag
    :redirect_invalid_sessions, # dry-run flag for redirecting web requests with invalid user_session cookies
    :redirect_invalid_sessions_enforcement, # enforcement flag for redirecting web requests with invalid user_session cookie
    :spokesd_instrumenter_collector, # enables spokesd instrumenter collector
    :issues_erb_template_render_tracking, # enables tracking of ERB template rendering in issues
    :primer_react_unified_portal_root, # enables unified portal root for Primer React
    :use_javascript_modules, # enables the "module" type for all JavaScript script tag bundles
    :control_access_retry_instrumentation, # add datadog metrics for authzd control access retries
    :token_scanning_use_staging, # enables token scanning to use staging environment for existing assessment check (needed for rendering Organization#scan_secret_leaks_banner)
    :command_palette_deprecation_notice, # enables the command palette deprecation notice
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
    :vitess_append_max_execution_time_comment_repositories, # appends MAX_EXECUTION_TIME optimizer hint to relevant queries
    :vitess_use_new_max_execution_time_repositories, # appends MAX_EXECUTION_TIME optimizer hint to relevant queries, using the new timeout value
    :vitess_append_max_execution_time_comment_repositories_actions_checks, # appends MAX_EXECUTION_TIME optimizer hint to relevant queries
    :vitess_use_new_max_execution_time_repositories_actions_checks, # appends MAX_EXECUTION_TIME optimizer hint to relevant queries, using the new timeout value
    :vitess_append_max_execution_time_comment_repositories_pushes_sharded, # appends MAX_EXECUTION_TIME optimizer hint to relevant queries
    :vitess_use_new_max_execution_time_repositories_pushes_sharded, # appends MAX_EXECUTION_TIME optimizer hint to relevant queries, using the new timeout value
    :vitess_append_max_execution_time_comment_token_scanning_service_prod, # appends MAX_EXECUTION_TIME optimizer hint to relevant queries
    :vitess_use_new_max_execution_time_token_scanning_service_prod, # appends MAX_EXECUTION_TIME optimizer hint to relevant queries, using the new timeout value
    :vitess_append_max_execution_time_comment_lodge, # appends MAX_EXECUTION_TIME optimizer hint to relevant queries
    :vitess_use_new_max_execution_time_lodge, # appends MAX_EXECUTION_TIME optimizer hint to relevant queries, using the new timeout value
    :copilot_coding_agent_task_indicator, #enables copilot coding agent status indicator
    :codespaces_proxima_enablement, # enables codespaces on proxima
    :erp_preview, # enables the Enterprise Role and Permissions feature set for preview users
    :erp_staffship, # enables the Enterprise Role and Permissions feature set specifically for staff users
    :enterprise_teams_org_assignment, # enables business teams to be granted organization role assignments
    :erp_preview_enterprise_teams_org_assignment, # enables business teams to be granted organization role assignments
    :erp_staffship_enterprise_teams_org_assignment, # enables business teams to be granted organization role assignments for staff users
    :enterprise_teams_esm, # enable business teams to be granted Enterprise Security Manager
    :erp_staffship_enterprise_teams_esm, # enable business teams to be granted Enterprise Security Manager for staff users
    :erp_preview_enterprise_teams_esm, # enable business teams to be granted Enterprise Security Manager for preview users
    :copilot_global_agent_button, # enables the dedicated global agent panel button in the site header
    :copilot_global_agent_button_popover, # enables the dedicated global agent panel button popover
    :copilot_global_agent_button_popover_ignore_dismiss, # enables the dedicated global agent panel button popover but ignores dismissing for testing
    :repos_relevance_page, # enables the repos relevance icons on the header and global sidebar
    :copilot_sku_isolation_use_public_user, # dynamically calculates Copilot URLs based on the user's SKU
    :copilot_sku_isolation_use_public_user_perf, # uses cached public user for calculating Copilot URL
    :flipper_vexi_proxy_redirect_percentage_of_actors_value, # temporary feature flags for flipper -> vexi migration used in various places
    :flipper_vexi_proxy_redirect_percentage_of_time_value, # temporary feature flags for flipper -> vexi migration used in various places
    :flipper_vexi_proxy_redirect_actors_value, # temporary feature flags for flipper -> vexi migration used in various places
    :flipper_vexi_proxy_redirect_off, # temporary feature flags for flipper -> vexi migration used in various places
    :flipper_vexi_proxy_redirect_on, # temporary feature flags for flipper -> vexi migration used in various places
    :coding_agent_in_proxima, # enables Copilot coding agent usage in Proxima
  ].flatten.to_set.freeze
end
