# typed: strict
# frozen_string_literal: true

require "active_job/job_class_actor"

class VexiSandboxController < ApplicationController # rubocop:todo GitHub/ControllersShouldHaveTests
  # CAP not required, this is an employee-only controller for testing the Vexi Feature Flag Client
  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  before_action :only_allow_staff_in_dotcom_or_stafftools_tenant_in_proxima

  preload_features [
    :vexi_sandbox_no_proxy_test_flag_1
  ].freeze

  helper_method :flipper_enabled_check, :flipper_square_bracket_check, :flipper_actor_check, :permitted_params

  NAV_OPTIONS = T.let(%w[landing vexi_with_preload vexi_with_preload_directly_from_adapter vexi_test vexi_debug vexi_actors], T::Array[String])

  SANDBOX_FEATURE_FLAGS_PRELOAD = T.let([
    # flipper preloaded flags
    *ApplicationController::PreloadFeatureFlagsDependency::APPLICATION_LAYOUT_FEATURES,

    # platform flags
    :gql_field_tracer,
    :persisted_tracer_mode,
    :persisted_tracer_debug_mode,
    :gql_n_plus_one_tracer,
    :gql_read_arguments_from_replicas,
    :gql_run_native_analyzers,
    :use_new_graphql_visibility_checks,
    :graphql_track_elastomer_queries,
    :gql_parse_query_with_escape,

  # client side preload flags
  *GitHub::ClientSideFeatureFlags::FLAGS,

  # comment feature flags
  *Issues::Comments::PRELOAD_FEATURES,

  # mobile feature flags
  *Mobile::ClientPublicApiFeatureFlags::FLAGS,

  # flags from other parts of github
  :actions_workflow_list_pinning,
  :custom_roles,
  :show_spammy_issues_to_staff,
  :consolidate_open_issue_and_pr_counts,
  :commit_avatar_stack_view_component,
  :issues_service_mutative_actions_rate_limits,
  :issues_service_mutative_actions_rate_limits_new_max,
  :issues_rate_limit_circuit_breaker,
  :dashboard_favorites,
  :disable_discussions_notifications,
  :slash_commands,
  :structured_issue_comment_templates,
  :issue_composer_security_link,
  :disable_azure_exp_cache,
  :notifications_async_discussions_subscription_button,
  :emu_vss_business,
  :discussions_copilot_summary,
  :skip_anon_jump_to_suggestions_enabled,
  :remove_shelf_limited_paths,
  :preload_domain_by_name_and_owner,
  :copilot_summary_ga,
  :copilot_summary_larger_context,
  :copilot_summary_send_all_comments,
  :feeds_exp_persistent_conn,
  :otel_rack_middleware,
  :allow_internal_org_config_repo_if_public_repos_disabled,
  :global_health_files_repository_loader_new_fetch_implementation,
  :copilot_conversational_ux_license_check,
  :copilot_for_partners,
  :copilot_natural_language_github_search,
  :add_notranslate_class,
  :issues_graph_api_disable_denormalized_read,
  :sparkle_votes,
  :sparkle_votes_opt_out,
  :discussions_top_filter_only_unlocked,
  :enterprise_banners_repo_level,
  :oidc_policy_enforced,
  :api_insights_rest,
  :optimize_single_repo_filter,
  :proxima_repository_advisories,
  :bus_ids_exclude_billing_manager_valid_license,
  :stacks_toggle,
  :skip_open_graph_url_encoding,
  :notifyd_label_subscriptions,
  :two_factor_checkup,
  :notifications_async_watch_repo_button,
  :authenticated_avatars,
  :owner_scoped_github_apps,
  :stafftools_tenant_use_parameter,
  :read_tree_entries_git,
  :spokes_api_ref_to_sha,
  :spokesd_request_timeout_header,
  :insights_codeblocks,
  :pull_request_single_subscription,
  :issues_react,
  :new_pulls_dashboard,
  :pull_request_sub_triggers,
  :use_pull_request_subscriptions_enabled,
  :author_association_internal_repository,
  :cap_filter_optimization,
  :cap_two_factor_filter,
  :merge_queue,
  :merge_queue_extra_branch_protection_settings,
  :previewable_form_component,
  :extract_checklists,
  :tasklist_block_soft_limits,
  :tasklist_block_hard_limits,
  :tasklist_block_sync_check,
  :issue_hierarchy_state,
  :issues_copilot_summary,
  :issues_graph_api_concurrent_faraday,
  :notifyd_only_assigned_push_notifications,
  :fuzzy_label_picker,
  :issue_summarization,
  :reactions_position,
  :convert_to_tasklist_block,
  :issue_mention_filter_load_installation_for_source_repo,
  :notifications_async_issues_subscription_button,
  :check_missing_pull_request_on_issue_load,
  :graphql_preload_business_user_accounts,
  :graphql_memoize_actor_limiter,
  :ghost_pilot_pr_autocomplete,
  :display_comment_actions,
  :may_post_comment_actions,
  :authnd_experiment,
  :cpq_check,
  :tasklist_block_morpheus,
  :track_mobile_query_name,
  :cap_pats_policy_enforcement,
  :return_oidc_orgs_from_saml_enforcement_policy,
  :two_factor_cap_enforcement,
  :verified_device_enforcement_opt_out,
  :ignorable_team_notifications,
  :encrypt_as_plaintext_user_weak_password_check_result,
  :issues_react_inbox_tabs,
  :notification_inbox,
  :notifyd_enable_gist_thread_subscriptions,
  :notifyd_primary_gist,
  :munger_client_get_option_defaults,
  :notifications_a11y_search_box_migration,
  :turn_off_unwatch_suggestions,
  :auto_merge,
  :mergebox_react_partial,
  :read_from_merge_box_json_api,
  :prx_commits,
  :prx_files,
  :prx_files_ssr,
  :graphql_subscriptions,
  :issues_react_prefetch,
  :codespaces_automated_testing,
  :actions_custom_image,
  :larger_runners_custom_image_generation,
  :codespaces_developer,
  :site_premium_support_redesign,
  :insights_api_local_development,
  :sub_issues,
  :org_feature_helper,
  :project_sculk,
  :memex_without_limits_limited_public_beta_banner_safe_rollout,
  :copilot_metered_enterprise,
  :log_notifications_unauthorized_accounts,
  :saml_scope_private_resources_to_org,
  :first_party_oauth_app_restrictions,
  :policies,
  :dependency_graph_dgp_backed_npm_alerts,
  :disable_code_scanning,
  :memex_table_without_limits,
  :ip_allowlist_user_level_enforcement,
  :discussions_release,
  :ugc_inline_machine_translation,
  :api_insights,
  :actions_performance_metrics,
  :actions_usage_metrics,
  :api_insights_async,
  :api_insights_public_feedback,
  :api_insights_use_secondary_tabular_input,
  :api_insights_owner_bypass,
  :azure_exp_staffbar,
  :command_palette_commands,
  :permission_enforcer_with_caching,
  :actions_usage_metrics_owner_bypass,
  :staff_cookie_default_to_canary,
  :memex_charts_basic_allow,
  :memex_historical_charts_on_assignees_milestones,
  :tasklist_tracked_by_redesign,
  :memex_group_by_multi_value_changes,
  :memex_resync_index,
  :memex_chart_cards_insights,
  :memex_disable_draft_issue_file_upload,
  :memex_disable_autofocus,
  :issue_types,
  :memex_status_updates_notifications,
  :mwl_beta_optout,
  :mwl_filter_bar_validation,
  :memex_mwl_swimlanes,
  :issues_react_ui_commands_migration,
  :issues_react_logged_out,
  :memex_side_panel_query,
  :memex_mwl_unique_filter_suggestions,
  :memex_mwl_table_cell_perf,
  :memex_new_bulk_update_ux,
  :memex_table_without_limits_csv_export,
  :memex_omnibar_prioritize_create_issue,
  :memex_mwl_insights,
  :memex_paginated_archive,
  :memex_sync_write_to_es,
  :memex_project_without_limits_public_beta,
  :optimize_single_memex_hierarchy_prefill,
  :memex_project_consistency_score_ignore_inconsistent_fields,
  :profiles_write_to_target,
  :memex_table_without_limits_disabled,
  :memex_mwl_spam_redaction,
  :memex_use_mwl_redactions
], T::Array[Symbol])

  VEXI_FEATURE_FLAGS = T.let([
    :vexi_sandbox_no_proxy_test_flag_fully_disabled,
    :vexi_sandbox_no_proxy_test_flag_100_of_actors,
    :vexi_sandbox_no_proxy_test_flag_100_of_calls,
    :vexi_sandbox_no_proxy_test_flag_custom_group,
    :vexi_sandbox_no_proxy_test_flag_does_not_exist,
  ], T::Array[Symbol])

  FLIPPER_FEATURE_FLAGS = T.let([
    :vexi_sandbox_test_via_flipper_proxy_1,
    :vexi_sandbox_test_via_flipper_proxy_2,
    :vexi_sandbox_test_via_flipper_proxy_3,
  ], T::Array[Symbol])

  sig { void }
  def index
    set_nav_breadcrumb ContextRegion::BasicCrumb.new(nil, label: "Vexi Sandbox")

    page = permitted_params[:nav_option] || "landing"
    if !NAV_OPTIONS.include?(page)
      page = "landing"
    end

    vexi_checks = []
    flipper_checks = []

    if page == "landing"
      vexi_checks = VEXI_FEATURE_FLAGS.each_with_object([]) do |feature_flag_name, checks|
        checks << vexi_check(feature_flag_name)
        checks << vexi_check(feature_flag_name, [current_user])
      end

      flipper_checks = FLIPPER_FEATURE_FLAGS.each_with_object([]) do |feature_flag_name, checks|
        checks << flipper_enabled_check(feature_flag_name)
        checks << flipper_square_bracket_check(feature_flag_name)
        checks << flipper_square_bracket_check(feature_flag_name, current_user)
        checks << flipper_actor_check(feature_flag_name, current_user)
      end
    elsif page == "vexi_with_preload"
      FeatureFlag.vexi.preload(
        VEXI_FEATURE_FLAGS + FLIPPER_FEATURE_FLAGS + SANDBOX_FEATURE_FLAGS_PRELOAD,
        fetch_directly_from_adapter: false,
        cache_without_expiry: true,
        instrumentation_properties: { "code.namespace": self.class.name&.underscore },
      )

      vexi_checks = VEXI_FEATURE_FLAGS.each_with_object([]) do |feature_flag_name, checks|
        checks << vexi_check(feature_flag_name)
        checks << vexi_check(feature_flag_name, [current_user])
      end

      flipper_checks = FLIPPER_FEATURE_FLAGS.each_with_object([]) do |feature_flag_name, checks|
        checks << flipper_enabled_check(feature_flag_name)
        checks << flipper_square_bracket_check(feature_flag_name)
        checks << flipper_square_bracket_check(feature_flag_name, current_user)
        checks << flipper_actor_check(feature_flag_name, current_user)
      end
    elsif page == "vexi_with_preload_directly_from_adapter"
      FeatureFlag.vexi.preload(
        VEXI_FEATURE_FLAGS + FLIPPER_FEATURE_FLAGS + SANDBOX_FEATURE_FLAGS_PRELOAD,
        fetch_directly_from_adapter: true,
        cache_without_expiry: true,
        instrumentation_properties: { "code.namespace": self.class.name&.underscore },
      )

      vexi_checks = VEXI_FEATURE_FLAGS.each_with_object([]) do |feature_flag_name, checks|
        checks << vexi_check(feature_flag_name)
        checks << vexi_check(feature_flag_name, [current_user])
      end

      flipper_checks = FLIPPER_FEATURE_FLAGS.each_with_object([]) do |feature_flag_name, checks|
        checks << flipper_enabled_check(feature_flag_name)
        checks << flipper_square_bracket_check(feature_flag_name)
        checks << flipper_square_bracket_check(feature_flag_name, current_user)
        checks << flipper_actor_check(feature_flag_name, current_user)
      end
    elsif page == "vexi_test"
      vexi_checks = VEXI_FEATURE_FLAGS.each_with_object([]) do |feature_flag_name, checks|
        checks << vexi_check(feature_flag_name)
        checks << vexi_check(feature_flag_name, [current_user])
      end
    elsif page == "vexi_debug" && permitted_params[:feature_flag_name].present?
      feature_flag_name = permitted_params[:feature_flag_name]

      unless feature_flag_name.start_with?("vexi_sandbox_")
        return redirect_to(_vexi_sandbox_index_path(nav_option: page))
      end

      actor_names = permitted_params[:actors].split(",").map(&:strip)
      actors = actor_names.map do |actor_name|
        GitHub::Resources.find_by_uri(actor_name)
      end.compact

      vexi_checks = [vexi_check(feature_flag_name, actors)]
    elsif page == "vexi_actors"
      actors = [
        ClusterAsActor.new("test_cluster"), # app/jobs/cluster_as_actor.rb
        Platform::MutationActor.new(Platform::Mutations::CreateIssue), # app/platform/mutation_actor.rb
        ActiveJob::JobClassActor.new(HydroMessageJob), # lib/active_job/job_class_actor.rb
        Alloy::AppActor.new("test_app"), # lib/alloy/app_actor.rb
        Events::ParentAsActor.new("test_parent"), # lib/events/parent_as_actor.rb
        GitHub::FlipperHost.new("test_host"), # lib/github/flipper_host.rb
        GitHub::FlipperRole.new("test_role"), # lib/github/flipper_role.rb
        GitHub::FlipperSite.new("test_site"), # lib/github/flipper_site.rb
        GitHub::Aqueduct::CompositeBackend::Actor.new(hostname: "test_host", pid: 1), # lib/github/aqueduct/composite_backend.rb # Note: This includes a value for the minute so will not be stable
        # GitHub::DGit::Delegate,  # lib/github/dgit/delegate.rb
        GitHub::DGit::Util::NetworkIdActor.new("test_network_id"), # lib/github/dgit/util.rb
        GitHub::StreamProcessors::VulnerabilityExposure::RepositoryFlipperActor.new(1), # lib/github/stream_processors/vulnerability_exposure.rb
        GitHub::Unsullied::Wiki.new(Repository.new(id: 1)), # lib/github/unsullied/wiki.rb
        Stratocaster::EventTypeActor.new("test_event_type", "test_action"), # lib/stratocaster/event_type_actor.rb
        Environment.new(id: 1), # packages/actions/app/models/environment.rb
        Business.new(id: 1), # packages/business/app/models/business.rb
        OauthApplication.default, # packages/app_security/app/models/oauth_application.rb
        OauthAuthorization.new(id: 1), # packages/app_security/app/models/oauth_authorization.rb
        UserSession.new(id: 1), # packages/app_security/app/models/user_session.rb
        IntegrationInstallation.new(id: 1), # packages/apps/app/models/integration_installation.rb
        Integration.new(id: 1), # packages/apps/app/models/integration.rb
        ScopedIntegrationInstallation::RepositoryFlipperActor.new(1), # packages/apps/app/models/scoped_integration_installation/repository_flipper_actor.rb
        Customer.new(id: 1), # packages/billing/app/models/customer.rb
        Billing::ZuoraWebhook.new(id: 1), # packages/billing/app/models/billing/zuora_webhook.rb
        Copilot::CopilotApi::IntegrationActor.new("test_integration"), # packages/copilot/app/models/copilot/copilot_api/integration_actor.rb
        Copilot::CopilotApi::TrackingIdActor.new("test_tracking_id"), # packages/copilot/app/models/copilot/copilot_api/tracking_id_actor.rb
        Storage::Uploadable::UploadableFlipperFlag.new(FakeUploadable.new), # packages/data/app/models/storage/uploadable/uploadable_flipper_flag.rb
        Gist.new(id: 1), # packages/gist/app/models/gist.rb
        FlipperSession.new(1), # packages/management_tools/app/models/flipper_session.rb
        Repository.new(id: 1), # packages/management_tools/app/models/repository/feature_flags_dependency.rb
        # TradeControls::AbstractTradeScreeningDependency # packages/management_tools/app/models/trade_controls/abstract_trade_screening_dependency.rb this looks to be just included in other models (User, Org, Business) and not initialized directly
        User::CurrentVisitorActor.new("GH1.1.1234.1234"), # packages/management_tools/app/models/user/current_visitor_actor.rb
        User::EmailSuffixActor.from_email_address("monalisa+test.o2MeJz9dp@github.com"), # packages/management_tools/app/models/user/email_suffix_actor.rb
        current_user, # packages/management_tools/app/models/user/feature_flag_methods.rb
        NotificationSummary.new(list_id: 1), # packages/notifications/app/models/notification_summary.rb
        Newsies::NotificationEntry.new(user_id: 1), # packages/notifications/app/models/newsies/notification_entry.rb
        Newsies::SavedNotificationEntry.new(user_id: 1), # packages/notifications/app/models/newsies/saved_notification_entry.rb
        Team.new(id: 1), # packages/orgs/app/models/team.rb
        Organization.new(id: 1), # packages/orgs/app/models/organization/feature_flag_dependency.rb
        MemexProject.new(id: 1), # packages/planning/app/models/memex_project.rb
        # Profiles::User::BaseLayoutData # packages/profiles/app/models/profiles/user/base_layout_data.rb
        UserProgrammaticAccess.new(id: 1), # packages/programmatic_access/app/models/user_programmatic_access.rb
        PersonalReminder.new(id: 1), # packages/pull_requests/app/models/personal_reminder.rb
        Reminder.new(id: 1), # packages/pull_requests/app/models/reminder.rb
        BulkReposIndexJob::AdminnedOrgIdActor.new(1), # packages/repositories/app/jobs/bulk_repos_index_job.rb
        RepositoryNetwork.new(id: 1), # packages/repositories/app/models/repository_network.rb
        Repository.new(id: 1), # packages/repositories/app/models/repository.rb
        Repositories::AssociatedRepositoriesDependency::AssociatedRepositories::AdminnedOrgIdActor.new(1), # packages/repositories/app/models/repositories/associated_repositories_dependency.rb
        Repositories::Domain::BadActorGate::DomainMethodActor.new("test_domain", :test_method, 1, 1), # packages/repositories/app/public/repositories/domain/bad_actor_gate.rb
        RepositoryVulnerabilityAlert::RepositoryFlipperActor.new(1), # packages/security_products/app/models/repository_vulnerability_alert.rb
        SecurityCenter::FlipperActorAdapters::Repository.new(1), # packages/security_products/app/models/security_center/flipper_actor_adapters.rb
        SecurityCenter::FlipperActorAdapters::Organization.new(1), # packages/security_products/app/models/security_center/flipper_actor_adapters.rb
        SecurityCenter::FlipperActorAdapters::Business.new(1), # packages/security_products/app/models/security_center/flipper_actor_adapters.rb
        Vulnerability.new(id: 1), # packages/security_products/app/models/vulnerability/shared_methods.rb
        Hook.new(id: 1), # packages/webhooks/app/models/hook.rb
        Hook::ParentAsActor.new("test_parent"), # packages/webhooks/app/models/hook.rb
        Hook::EventAsActor.new("test_event"), # packages/webhooks/app/models/hook.rbs
      ]

      vexi_checks = actors.each_with_object([]) do |actor, checks|
        flag_name = "vexi_sandbox_all_actors"
        checks << vexi_check(flag_name, [actor])
      end
    end

    render "vexi/sandbox/index", locals: { page: page, nav_options: NAV_OPTIONS, vexi_checks: vexi_checks, flipper_checks: flipper_checks }
  end

  private

  sig { returns(ActionController::Parameters) }
  memoize def permitted_params
    params.permit(:nav_option, :feature_flag_name, :actors, :submit, :cache_tracer, :ff_cache_tracer)
  end

  # Wraps Vexi enabled check and will output the feature flag name and also if it's enabled or there's an exception
  sig { params(feature_flag: T.any(Symbol, String), actors: T::Array[GitHub::VexiActor]).returns(T::Hash[Symbol, String]) }
  def vexi_check(feature_flag, actors = []) # rubocop:todo GitHub/UseRestfulActions
    code = if actors.present?
      "FeatureFlag.vexi.enabled?(#{feature_flag}, #{actors.map(&:vexi_id).join(", ")}))"
    else
      "FeatureFlag.vexi.enabled?(#{feature_flag})"
    end

    # Using T.unsafe here because of the Splat parameter
    # Workaround for https://sorbet.org/docs/error-reference#7019
    enabled = T.unsafe(FeatureFlag.vexi).enabled?(feature_flag, *actors) ? "enabled" : "disabled"

    { code: code, feature_flag: feature_flag, result: enabled }
  rescue => e # rubocop:disable Lint/GenericRescue
    Failbot.report!(e)
    { code: code, feature_flag: feature_flag, result: e.message }
  end

  # Wraps GitHub.flipper.enabled?() check and will output the feature flag name and also if it's enabled or there's an exception
  sig { params(feature_flag: T.any(Symbol, String)).returns(T::Hash[Symbol, String]) }
  def flipper_enabled_check(feature_flag)
    code = "GitHub.flipper.enabled?(#{feature_flag})"
    enabled = GitHub.flipper.enabled?(feature_flag) ? "enabled" : "disabled"
    { code: code, feature_flag: feature_flag, result: enabled }
  rescue => e # rubocop:disable Lint/GenericRescue
    Failbot.report!(e)
    { code: code, feature_flag: feature_flag, result: e.message }
  end

  # Wraps GitHub.flipper[:feature].enabled?() check and will output the feature flag name and also if it's enabled or there's an exception
  sig { params(feature_flag: T.any(Symbol, String), actor: T.nilable(GitHub::FlipperActor)).returns(T::Hash[Symbol, String]) }
  def flipper_square_bracket_check(feature_flag, actor = nil)
    enabled = "disabled"
    code = ""
    if actor.nil?
      code = "GitHub.flipper[#{feature_flag}].enabled?"
      enabled = GitHub.flipper[feature_flag].enabled? ? "enabled" : "disabled"
    else
      code = "GitHub.flipper[#{feature_flag}].enabled?(#{actor.flipper_id})"
      enabled = GitHub.flipper[feature_flag].enabled?(actor) ? "enabled" : "disabled"
    end

    { code: code, feature_flag: feature_flag, result: enabled }
  rescue => e # rubocop:disable Lint/GenericRescue
    Failbot.report!(e)
    { code: code, feature_flag: feature_flag, result: e.message }
  end

  # Wraps actor.feature_enabled?() check and will output the feature flag name and also if it's enabled or there's an exception
  sig { params(feature_flag: T.any(Symbol, String), actor: FeatureFlag::IFeatureTarget).returns(T::Hash[Symbol, String]) }
  def flipper_actor_check(feature_flag, actor)
    code = "(#{T.unsafe(actor).flipper_id}).feature_enabled?(#{feature_flag})"
    enabled = actor.feature_enabled?(feature_flag) ? "enabled" : "disabled"

    { code: code, feature_flag: feature_flag, result: enabled }
  rescue => e # rubocop:disable Lint/GenericRescue
    Failbot.report!(e)
    { code: code, feature_flag: feature_flag, result: e.message }
  end

  sig { void }
  def only_allow_staff_in_dotcom_or_stafftools_tenant_in_proxima
    # Don't allow in GHES at all (this is also guarded in the routes)
    render_404 if GitHub.enterprise?

    # If we're in a multi-tenant enterprise, only allow staff in the stafftools tenant.
    # We aren't checking for employee status here because we aren't employees in these tenants.
    # Being logged into the stafftools tenant is enough since only staff have access to it.
    if GitHub.multi_tenant_enterprise?
      render_404 unless GitHub::CurrentTenant.stafftools_tenant?
      render_404 unless logged_in?
    else
      # Otherwise, only allow staff in dotcom
      employee_only
    end
  end

  class FakeUploadable
    sig { returns(String) }
    def storage_migration_id
      "test_migration_id"
    end
  end
end
