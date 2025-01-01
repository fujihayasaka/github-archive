# typed: true
# frozen_string_literal: true

module ApplicationController::PreloadFeatureFlagsDependency
  extend ActiveSupport::Concern
  extend T::Helpers
  requires_ancestor { ApplicationController }

  APPLICATION_LAYOUT_FEATURES = [
    :primer_octicon_cache,
    :cap_2fa_policy_enabled,
    :custom_search_commands, # site/header/global_search
    :emu_visibility_policy,
    :memex_insights,
    :ko_homepage_translation,
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
    :turbo_experiment_risky, # enable risky turbo experiments
    :preload_warppipe_flags, # enable preloading feature flags used in warppipe filters
    :glb_ddos_anon_ip_path_limit, # DDoS rate limiter.
    :bulwark_two_factor_required_feature, # enable two factor authentication requirement for bulwark
    :two_factor_holiday_warning_banner, # global flag for 2FA holiday warning banner
    :gists_two_factor_holiday_warning_banner, # global flag for 2FA holiday warning banner in gists
    :scim_rate_limiting_multiplier, # increasing rate limit for SCIM API calls for enterprise accounts
    :tenant_namespacing, # used for loading users via display or unique logins through current tenant
    :reset_tenant_context, # used to force reset the tenant context per request
    :active_job_preserve_tenant_context_method, # whether to use the new method to preserve tenant context in ActiveJob
    :disable_proxima_employee_team_check, # disables User#employee? in Proxima
    :tenant_selection_logging_context, # tags logs with tenant context from tenant selection middleware
    :tenant_on_github_v1_request_hydro_event, # tag the github_v1_request event with tenant name + ID in Hydro middleware
    *GitHub::OriginTrials.current_trials.map(&:feature_flag),
    :react_next, # determines if we should load the next version of react bundle
    :use_alloy_manifest, # send files to alloy using a manifest
    :disable_turbo_visit, # disables Turbo Drive
    :report_hydro_web_vitals, # controls whether to report web vitals to Hydro
    :custom_inp, # Enables custom INP implementation
    :alloy_enable_caching, # Enables Alloy caching for an app's request
    :remove_child_patch, # Enables the removeChild patch for React.
    :notifications_indicator_async_fetch, # determines if we should fetch the notifications icon status asynchronously
    :notifications_async_top_shelf, # whether to always load the notifications top shelf asynchronously or not
    :react_lazy_fetching, # whether to enable React's payload preloading
    :copilot_dotcom_chat,
    :copilot_chat_rails_anchor, # use a rails rendered anchor to trigger copilot chat experience
    :copilot_floating_button, # use a floating button to trigger copilot chat experience
    :copilot_workspace, # display Copilot Workspace button in issue sidebar
    :hydro_request_new_mysql, # whether to collect additional MySQL query stats in hydro github.v1.Request events
    :emu_user_session_expiration, # whether user sessions should have hard expirations based on EMU external identity sessions
    :emu_actions_tab_policy, # whether to disable actions tab for EMUs with disabled self-hosted runners
    :primer_input_border_contrast, # enables higher contrast border colors for form components
    :primer_button_border_contrast, # enables higher contrast border colors for default Primer buttons
    :issues_react_global_add, # whether to enable the new global issue add button in the site header
    :marketing_cookie_consent_banner, # enables cookie consent management
    :monaspace_font, # enables monaspace font for users who have it locally installed
    :sdn_organization_suspension_v3, # enables programmatic public repo archive for sdn org suspensions
    :emu_policies_helper_ability_delegate, # enables ability delegate for emu policies helper
    :rev_parse_git, # enables a Git-based implementation for the rev_parse Gitrpc endpoint
    :eager_load_global_nav, # Removes placeholders in global nav and eager loads content
    :react_global_create_menu, # Render the React version of the Create Menu in the Global Nav
    :enterprise_access_verification_beta, # enables a new CAP policy to verify the Enterprise specified in a security header matches the actor private beta
    :enterprise_access_header_verification_login, # enables a check for the business header passed in as part of the request, valid for EMUs only
    :spokesd_filter_routes, # changes the filtering of routes for gitrpc using spokesd liveness check and circuit breaker
    :primer_button_break_line, # allow primer beta button label text to break line
    :filter_prefetch_suggestions, # enables prefetched suggestions in the Filter component
    :disable_mathjax, # functions as a long-lived emergency shutoff in case of MathJax incidents
    :react_ssr_remove_fields_from_alloy_request, # enables removing graphql fields from the Alloy request in SSR
    :issues_react_use_defer_directive, # enables using the defer directive in the new issues experience
    :delay_global_notice_next_refresh_job, # delays the next global notice refresh job
    :metrics_details_metric, # more granular metrics tracking metrics
    :actionable_two_factor_security_checkup, # enables the actionable two factor security checkup global banners
    :rpc_mysql_dist_time_metric_extra_tags, # enables new rpc.mysql.extra_tags.dist.time metric
    :throttle_expensive_gitrpc_calls, # enables throttling for expensive gitrpc calls
    :primer_react_action_list_item_as_button, # enables using buttons in action list items in Primer React
    :primer_react_css_modules_ga, # enables CSS Modules in Primer React for everyone
    :primer_react_css_modules_staff, # enables CSS Modules in Primer React for staff
    :primer_react_css_modules_team, # enables CSS Modules in Primer React for the team
    :primer_react_css_modules_css_layers, # enables CSS layers in CSS Modules in Primer React
    :magic_shell_caching, # powering layout caching
    :projects_classic_sunset_ui, # hides references to projects classic in the UI
    :projects_classic_sunset_override, # a support/staff-only flag to allow overriding the Projects (classic) sunset in the rare situation we need to still allow it to be accessible.
    :hydro_v1_request_double_publishing, # enables double publishing of hydro v1 request events to request-analytics
    :idp_cap_for_web, # adds external conditional access policy enforcement for web
    :idp_cap_for_web_enforcer, # adds external conditional access policy enforcement for web enforcer
    :log_applicable_external_conditional_access_policy, # logs the applicability of external conditional access policy
    :async_action_or_role_level_for_metrics, # publish metrics for async_action_or_role_level_for callsites
    :async_mcab_authorization_service, # use the async_mcab method in Authorization::Service
    :async_mcab_ability_dependency, # use the async_mcab method in repo Ability dependency's async_access_level_for
    :async_mcab_project_user_permission, # use the async_mcab method in Graphql Project object's user_permission field
    :ability_loader_size_metric, # publish metrics for the number of abilties requested in a single ability loader query
    :idp_cap_for_filters, # adds the external conditional access policy to the filters
    :rescue_exempt_check_cap, # enables the rescue exempt check for CAP
    :actor_id_result_batching, # enables actor id result batching for the actor ids query
    :request_cluster_queries_sampled_metric, # enables emitting a sampled version of the request.cluster.queries metric
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
    GitHub.flipper.preload(all_features)

    # preload features flags using vexi. Do not add feature flags to this list without talking to #feature-management first
    vexi_preload_features = []
    return if vexi_preload_features.empty?
    return unless GitHub.flipper[:vexi_feature_preloading].enabled?

    FeatureFlag.vexi.preload(vexi_preload_features, fetch_directly_from_adapter: false)
  end

  # Returns true by default when running in tests to skip preload.
  # This wrapper function allows tests that want to enable preload to do so via stubbing this method,
  # without needing to stub the entire GitHub::AppEnvironment.test? method, which can cause other side effects.
  def self.skip_feature_preload_in_tests?
    GitHub::AppEnvironment.test?
  end
end
