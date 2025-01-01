# typed: true
# frozen_string_literal: true

module ApplicationController::PreloadFeatureFlagsDependency
  extend ActiveSupport::Concern
  extend T::Helpers
  requires_ancestor { ApplicationController }

  APPLICATION_LAYOUT_FEATURES = [
    :primer_octicon_cache,
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
    :react_turbo_soft_navs, # whether to allow Turbo to manage React soft navigations from outside of a React app
    :run_split_ability_loader_experiment, # used in all platform::loaders::ability queries
    :split_ability_loader, # used in all platform::loaders::ability queries
    :copilot_dotcom_chat,
    :copilot_chat_rails_anchor, # use a rails rendered anchor to trigger copilot chat experience
    :copilot_immersive_v1, # use clean up of immersive chat
    :copilot_workspace, # display Copilot Workspace button in issue sidebar
    :copilot_workspace_skip_waitlist, # skip waitlist for Copilot Workspace
    :emu_user_session_expiration, # whether user sessions should have hard expirations based on EMU external identity sessions
    :emu_actions_tab_policy, # whether to disable actions tab for EMUs with disabled self-hosted runners
    :primer_primitives_experimental, # enables some experimental color changes for Primer primitives
    :issues_react_global_add, # whether to enable the new global issue add button in the site header
    :marketing_cookie_consent_banner, # enables cookie consent management
    :monaspace_font, # enables monaspace font for users who have it locally installed
    :sdn_organization_suspension_v3, # enables programmatic public repo archive for sdn org suspensions
    :emu_policies_helper_ability_delegate, # enables ability delegate for emu policies helper
    :rev_parse_git, # enables a Git-based implementation for the rev_parse Gitrpc endpoint
    :eager_load_global_nav, # Removes placeholders in global nav and eager loads content
    :react_global_create_menu, # Render the React version of the Create Menu in the Global Nav
    :enterprise_access_header_verification_login, # enables a check for the business header passed in as part of the request, valid for EMUs only
    :primer_button_break_line, # allow primer beta button label text to break line
    :primer_react_action_list_item_as_button, # enables using buttons in action list items in Primer React
    :primer_react_overlay_overflow, # enables responsive overlay with width overflows
    :primer_react_segmented_control_tooltip, # enables tooltip on SegmentedControl.IconButton
    :disable_mathjax, # functions as a long-lived emergency shutoff in case of MathJax incidents
    :issues_react_use_defer_directive, # enables using the defer directive in the new issues experience
    :issues_react_helper_logging_errors, # enables logging errors from graphql queries
    :global_notice_domain, # enables the new global notice domain
    :actionable_two_factor_security_checkup, # enables the actionable two factor security checkup global banners
    :throttle_expensive_gitrpc_calls, # enables throttling for expensive gitrpc calls
    :magic_shell_caching, # powering layout caching
    :belongs_to_repo_domain, # load Model#repository through domain interface
    :projects_classic_sunset_ui, # hides references to projects classic in the UI
    :projects_classic_sunset_override, # a support/staff-only flag to allow overriding the Projects (classic) sunset in the rare situation we need to still allow it to be accessible.
    :log_applicable_external_conditional_access_policy, # logs the applicability of external conditional access policy
    :private_avatars, # enables jwt signed private avatars
    :proxima_avatar_tenant_slug_fix,
    :via_domain_singleton,
    :enterprise_breadcrumbs, # flag for showing current enterprise in global nav. Also hides logo on sm viewports.
    :actor_id_result_batching, # enables actor id result batching for the actor ids query
    :cap_filter_consider_outside_collabs, # allows conditional access policies to be able to filter content for outside collaborators
    :site_turbo_disable, # Turbo disable for marketing pages
    :react_app_dvh, # uses dvh instead of vh for .react-app height calculation
    :session_cookie_analysis, # temporary logging during session authentication
    :disable_global_anonymous_search_count, # disables a very conservative global rate limit for anon search requests
    :override_fetch, # overrides the fetch function to always add the X-Requested-With header
    :copilot_chat_dashboard_entrypoint, # use the immersive entrypoint for copilot chat on the dashboard,
    :bundles_keep_css_modules, # used in the bundle helper to fix css modules being removed by react partial re-renders
    :copilot_custom_copilots, # enables the ability to have custom copilots
    :copilot_free_limited_user, # enables copilot free user experience
    :sdn_copilot_vnext, # enables the new Copilot trade controls SDN treatment
    :primer_prefers_contrast, # enables higher contrast if prefers contrast OS setting is set
    :report_authzd_indeterminates, # enabled error reporting for authzd indeterminate responses
    :run_authzd_cap_experiment, # enables the authzd cap experiment
    :run_authzd_cap_experiment_web, # enables the authzd cap experiment for web enforcer
    :run_authzd_cap_filter_experiment, # enables the authzd cap filter experiment
    :run_authzd_cap_filter_experiment_view, # enables the authzd cap filter experiment for view filter
    :only_validate_on_blur_migration, #adoption of more accessible auto-check behavior for one search setting
    :batch_business_org_abilities, # batch calls to abilities for orgs in a business
    :run_business_org_abilities_experiment, # enable running the experiment to batch calls to abilities for orgs in a business
    :navbar_hits_details, # enables additional tags on metrics produced via navbar_hit feature flag,
    :navbar_counter_caching, # enables caching of repo navbar counters for specific repositories
    :navbar_counter_caching_ttl_over5k, # used not as a feature flag, but as a run-time knob for changing the caching TTL
    :navbar_counter_caching_ttl_over1k, # used not as a feature flag, but as a run-time knob for changing the caching TTL
    :navbar_counter_caching_ttl_under1k, # used not as a feature flag, but as a run-time knob for changing the caching TTL
    :case_insensitive_label_ordering_gql, # Use case insensitive search in the labels field for issues
    :navbar_hits, # enables tracking of navbar hits,
    :issue_comments_api_use_collab_replica, # enables using the collab replica for issue comments
    :platform_loader_apm_spans, # enables generic APM tracking of platform loader calls
    :github_models_repo_tab, # show/hide GitHub Models tab on repo page
    :saml_enforcement_policy_experiment, # enables the experiment to use the new saml enforcement policy
    :spark_dashboard, # show/hide the new Spark dashboard
    :enterprise_teams_attributes_include_business_teams, # include business teams in authzd team attributes
    :ui_deploys, # enables loading JS from the separate UI deploy
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
