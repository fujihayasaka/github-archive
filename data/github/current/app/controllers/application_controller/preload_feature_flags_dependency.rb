# typed: true
# frozen_string_literal: true

module ApplicationController::PreloadFeatureFlagsDependency
  extend ActiveSupport::Concern
  extend T::Helpers
  requires_ancestor { ApplicationController }

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
    :react_router_next, # flag to rollout the upgarade to React Router v7
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
    :copilot_immersive_v1, # use clean up of immersive chat
    :copilot_workspace, # display Copilot Workspace button in issue sidebar
    :copilot_workspace_skip_waitlist, # skip waitlist for Copilot Workspace
    :emu_user_session_expiration, # whether user sessions should have hard expirations based on EMU external identity sessions
    :emu_actions_tab_policy, # whether to disable actions tab for EMUs with disabled self-hosted runners
    :primer_primitives_experimental, # enables some experimental color changes for Primer primitives
    :contribution_graph_borders_override, # enables the contribution graph borders override
    :issues_react_global_add, # whether to enable the new global issue add button in the site header
    :marketing_cookie_consent_banner, # enables cookie consent management
    :monaspace_font, # enables monaspace font for users who have it locally installed
    :emu_policies_helper_ability_delegate, # enables ability delegate for emu policies helper
    :rev_parse_git, # enables a Git-based implementation for the rev_parse Gitrpc endpoint
    :eager_load_global_nav, # Removes placeholders in global nav and eager loads content
    :react_global_create_menu, # Render the React version of the Create Menu in the Global Nav
    :global_nav_experiment, # related to this UI experiment: https://github.com/github/github/pull/372845
    :dashboard_nav_experiment, # related to this UI experiment: https://github.com/github/github/pull/372845
    :responsive_context_region, # enables the new responsive version of global nav's context region
    :enterprise_access_header_verification_login, # enables a check for the business header passed in as part of the request, valid for EMUs only
    :primer_button_break_line, # allow primer beta button label text to break line
    :primer_react_action_list_item_as_button, # enables using buttons in action list items in Primer React
    :primer_react_overlay_overflow, # enables responsive overlay with width overflows
    :primer_react_segmented_control_tooltip, # enables tooltip on SegmentedControl.IconButton
    :disable_mathjax, # functions as a long-lived emergency shutoff in case of MathJax incidents
    :issues_react_helper_logging_errors, # enables logging errors from graphql queries
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
    :copilot_free_limited_user, # enables copilot free user experience
    :copilot_premium_request_quotas, # enables copilot premium request quota tracking in the UI
    :sdn_copilot_vnext, # enables the new Copilot trade controls SDN treatment
    :primer_prefers_contrast, # enables higher contrast if prefers contrast OS setting is set
    :report_authzd_indeterminates, # enabled error reporting for authzd indeterminate responses
    :run_authzd_cap_experiment, # enables the authzd cap experiment
    :run_authzd_cap_experiment_web, # enables the authzd cap experiment for web enforcer
    :run_authzd_cap_filter_experiment, # enables the authzd cap filter experiment
    :run_authzd_cap_filter_experiment_view, # enables the authzd cap filter experiment for view filter
    :use_authzd_mesh_client, # use the authzd mesh client for authzd requests
    :use_authzd_mesh_enumerator_client, # use the authzd mesh enumerator_client for authzd requests
    :use_authzd_mesh_conditional_access_client, # use the authzd mesh conditional_access_client for authzd requests
    :use_authzd_persistent_excon_conditional_access_client, # use the persistent_excon faraday adapter for authzd cap client
    :use_authzd_mesh_controlaccess_client, # use the authzd mesh controlaccess_client for authzd requests
    :use_authzd_cap_in_test, # test only, 1 of 2 flags for explicit test opt-in to use authzd cap
    :skip_authzd_cap_in_test, # test only, 2 of 2 flags for explicit test opt-in to use authzd cap
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
    :batch_business_org_abilities, # batch calls to abilities for orgs in a business
    :run_business_org_abilities_experiment, # enable running the experiment to batch calls to abilities for orgs in a business
    :navbar_hits_details, # enables additional tags on metrics produced via navbar_hit feature flag,
    :navbar_counter_caching, # enables caching of repo navbar counters for specific repositories
    :navbar_counter_caching_invalidation, # enables invalidation of navbar counter cache for specific repositories
    :navbar_counter_caching_staleness_skip, # enables skipping staleness checks for navbar counter cache
    :navbar_counter_caching_ttl_long, # used not as a feature flag, but as a run-time knob for changing the caching TTL
    :navbar_counter_caching_ttl_medium, # used not as a feature flag, but as a run-time knob for changing the caching TTL
    :navbar_counter_caching_ttl_short, # used not as a feature flag, but as a run-time knob for changing the caching TTL
    :navbar_counter_caching_backend_redis, # use redis for caching repo navbar counters instead of memcached
    :navbar_counter_caching_sub_1k_medium_lower_bound, # determine lower bound for longer caching TTL for repositories with under 1000 open issues
    :endpoint_anon_blocked_actors, # feature flag used for blocking anonymous requests for specific endpoints based on IP address or JA3 hash
    :dotcom_web_blocked_ip_addresses, # feature flag used for blocking requests from certain IP addresses via GLB abuse blocking
    :dotcom_web_ip_addresses_blocking, # whether the blocking above is fully enabled or running in dry run mode
    :case_insensitive_label_ordering_gql, # Use case insensitive search in the labels field for issues
    :navbar_hits, # enables tracking of navbar hits,
    :authzd_test_flag, # CI only FF needed until Vexi interprocess flag syncing is enabled
    :enterprise_teams_org_membership_macro, # enables the org membership macro for authzd
    :enterprise_teams_org_membership_memex, # enables the org membership macro for memex read macro for authzd
    :github_models_repo_integration, # show/hide GitHub Models tab on repo page
    :github_models_repo_tab_on_public_repos, # show/hide GitHub Models tab on public repos
    :copilot_workbench, # show/hide Spark (known as `copilot_workbench`)
    :enterprise_teams_attributes_include_business_teams, # include business teams in authzd team attributes
    :ui_deploys, # enables loading JS/CSS from the separate UI deploy
    :ui_manifest_relay_query_names, # fetch relay query names/ids from the UI manifest instead of from disk
    :client_version_header, # enables the client version header for fetch requests
    :elasticsearch_semantic_indexing_issues, # allow ingesting new semantic indexing for issues
    :fetch_nonce_block, # enables blocking requests with mismatched fetch nonces
    :appearance_settings_logged_out_users, # enables appearance settings for increasing contrast
    :primer_react_select_panel_fullscreen_on_narrow, #  allows for the SelectPanel to go full-screen on narrow viewports
    :spokesd_use_httpv11, # switches one spokesd client from H2 to HTTP/1.1
    :bypass_pat_lifetime_policies_check, # bypasses the check for PAT lifetime policies
    :ip_allowlist_org_apps_access_business_target, # IP allowlist CAP - installation is on an organization, the Business has IP allowlist configured
    :disable_legacy_es_cluster_metric,  # disables emitting the `es_cluster` dd tag in lieu of the new `search_cluster` tag
    :redirect_invalid_sessions, # dry-run flag for redirecting web requests with invalid user_session cookies
    :redirect_invalid_sessions_enforcement, # enforcement flag for redirecting web requests with invalid user_session cookie
    :emu_cap_staff_user, # does not require EMU Ownership CAP for staff users
    :authorized_org_ids_from_session_for_oidc, # includes authorized org ids from session for OIDC
    :authzd_candidate_query_esm_checks, # enables authzd candidate query ESM checks
    :spokesd_instrumenter_collector, # enables spokesd instrumenter collector
  ].flatten.to_set.freeze

  class_methods do
    include Kernel

    # Public: Define an array of features that should be preloaded for this controller/action,
    # in order to avoid N calls to memcache (1 per feature per request).
    # This is meant to be called throughout the controller hierarchy in order to
    # avoid child controllers needing to worry about layout-level flag preloading.
    #
    # For now, features are only preloaded if the requested format is HTML, since
    # many feature checks occur in ERB layouts.
    #
    # features - The Array of symbols representing the features to preload.
    # only - Optional symbol or array of symbols representing the actions that
    #        should preload these features. If omitted, all actions in this controller will
    #        preload this list of features.
    #
    # Examples
    #
    #   preload_features [:my_whole_controller_needs_this]
    #   preload_features [:specific_feature], only: :index
    #   preload_features [:kind_of_specific_feature], only: [:index, :show]
    def preload_features(features, only: nil)
      T.bind(self, T.class_of(ApplicationController))
      if only
        Array(only).each do |action|
          new_set = features_to_preload_by_action[action].union(features)

          self.features_to_preload_by_action =
            self.features_to_preload_by_action.merge(action => new_set)
        end
      else
        self.features_to_preload += features.to_set
      end
    end
  end

  included do
    T.bind(self, Class)
    class_attribute :features_to_preload
    class_attribute :features_to_preload_by_action

    T.bind(self, T.class_of(ApplicationController))
    before_action :do_feature_preload

    self.features_to_preload = APPLICATION_LAYOUT_FEATURES.dup
    self.features_to_preload_by_action = HashWithIndifferentAccess.new { |k, v| k[v] = Set.new }
  end

  def do_feature_preload
    return unless request.format.try(:html?)
    return if GitHub.enterprise?

    # Preloading can be slow in tests, so we skip it by default there.
    return if ApplicationController::PreloadFeatureFlagsDependency.skip_feature_preload_in_tests?

    action_features = features_to_preload_by_action[action_name]
    general_features = features_to_preload
    all_features = action_features.union(general_features).to_a.sort

    FeatureFlag.vexi.preload(all_features, instrumentation_properties: {
      "code.namespace": self.class.name&.underscore,
    })
  end

  # Returns true by default when running in tests to skip preload.
  # This wrapper function allows tests that want to enable preload to do so via stubbing this method,
  # without needing to stub the entire GitHub::AppEnvironment.test? method, which can cause other side effects.
  def self.skip_feature_preload_in_tests?
    GitHub::AppEnvironment.test?
  end
end
