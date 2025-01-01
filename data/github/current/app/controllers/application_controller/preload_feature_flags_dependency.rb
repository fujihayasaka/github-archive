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
    :alloy_enable_caching, # Enables Alloy caching for an app's request
    :disable_react_ssr, # Disables SSR for user
    :notifications_indicator_async_fetch, # determines if we should fetch the notifications icon status asynchronously
    :react_lazy_fetching, # whether to enable React's payload preloading
    :run_batch_ability_loader_experiment, # used in all platform::loaders::ability queries
    :batch_ability_loader, # used in all platform::loaders::ability queries
    :copilot_dotcom_chat,
    :copilot_chat_rails_anchor, # use a rails rendered anchor to trigger copilot chat experience
    :copilot_dotcom_chat_ci_and_cb,
    :copilot_immersive_v1, # use clean up of immersive chat
    :copilot_workspace, # display Copilot Workspace button in issue sidebar
    :hydro_send_secondary_limiters_evaluated, # whether to send data for evaluated secondary limiters in hydro github.v1.Request events
    :emu_user_session_expiration, # whether user sessions should have hard expirations based on EMU external identity sessions
    :emu_actions_tab_policy, # whether to disable actions tab for EMUs with disabled self-hosted runners
    :primer_input_border_contrast, # enables higher contrast border colors for form components
    :primer_button_border_contrast, # enables higher contrast border colors for default Primer buttons
    :primer_primitives_experimental, # enables some experimental color changes for Primer primitives
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
    :primer_react_action_list_item_as_button, # enables using buttons in action list items in Primer React
    :primer_react_overlay_overflow, # enables responsive overlay with width overflows
    :disable_mathjax, # functions as a long-lived emergency shutoff in case of MathJax incidents
    :issues_react_use_defer_directive, # enables using the defer directive in the new issues experience
    :global_notice_domain, # enables the new global notice domain
    :actionable_two_factor_security_checkup, # enables the actionable two factor security checkup global banners
    :throttle_expensive_gitrpc_calls, # enables throttling for expensive gitrpc calls
    :magic_shell_caching, # powering layout caching
    :projects_classic_sunset_ui, # hides references to projects classic in the UI
    :projects_classic_sunset_override, # a support/staff-only flag to allow overriding the Projects (classic) sunset in the rare situation we need to still allow it to be accessible.
    :idp_cap_for_web, # adds external conditional access policy enforcement for web
    :log_applicable_external_conditional_access_policy, # logs the applicability of external conditional access policy
    :idp_cap_for_filters, # adds the external conditional access policy to the filters
    :private_avatars, # enables jwt signed private avatars
    :via_domain_singleton,
    :async_domain_assoc, # load async_* associations through domain interface
    :idp_cap_web_configurable_allowed, # enables the IdP CAP for web configurable option for existing IdP CAP customers
    :actor_id_result_batching, # enables actor id result batching for the actor ids query
    :flipper_vexi_proxy_redirect, # determines whether or not a feature flag should use flipper or vexi
    :cap_filter_consider_outside_collabs, # allows conditional access policies to be able to filter content for outside collaborators
    :selective_ssr, # enables selective SSR for react apps
    :site_turbo_disable, # Turbo disable for marketing pages
    :enforce_ip_allowlist_copilot_token_endpoint, # allows ip_allowlist policy enforcement when authenticating via a generate_copilot_cdn_token capable app
    :react_app_dvh, # uses dvh instead of vh for .react-app height calculation
    :session_cookie_analysis, # temporary logging during session authentication
    :disable_global_anonymous_search_count, # disables a very conservative global rate limit for anon search requests
    :author_association_improvements, # improve the author association behaviour on comments
    :override_fetch, # overrides the fetch function to always add the X-Requested-With header
    :copilot_chat_dashboard_entrypoint, # use the immersive entrypoint for copilot chat on the dashboard,
    :vexi_feature_preloading, # used to control whether feature flags are preloaded using vexi
    :bundles_keep_css_modules, # used in the bundle helper to fix css modules being removed by react partial re-renders
    :team_default_scope, # used in all Team queries to properly scope them to this class only as BusinessTeam was introduced as a child class using STI
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

    if self.respond_to?(:current_user) && current_user
      return if !current_user.feature_enabled?(:vexi_feature_preloading)
    else
      return if !GitHub.flipper[:vexi_feature_preloading].enabled?
    end

    FeatureFlag.vexi.preload(all_features, fetch_directly_from_adapter: false, instrumentation_properties: {
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
