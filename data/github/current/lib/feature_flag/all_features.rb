# typed: strict
# frozen_string_literal: true

module FeatureFlag
  class AllFeatures
    sig { returns(T::Array[Symbol]) }
    def self.exclusion_list
      exclusion_list = T.let([], T::Array[Symbol])

      # Long lived feature flag that blocks traffic using Api::RouteActor,
      # meant to be enabled only for specific actors.
      # If this is fully on it will block all unauthenticated traffic to API endpoints
      exclusion_list << :api_force_auth_by_route
      # Long lived feature flag that blocks traffic using Api::HashedRouteActor,
      # meant to be enabled only for specific actors.
      # If this is fully on it will block all unauthenticated traffic to API endpoints
      exclusion_list << :api_block_anonymous_by_hashed_route

      # Per-route enforcement flag using ControllerRouteActor.
      # If fully on it will block all sessionless requests with Authorization headers.
      exclusion_list << :block_sessionless_auth_header_enforcement

      exclusion_list << :registry_disable
      exclusion_list << :registry_alpha_disabled

      # Circuit breaker kill switch for creating codespaces - we don't want
      # this enabled during tests that attempt to create codespaces.
      exclusion_list << :disable_codespace_creation

      # Abuse blocking flag for email domains — must only be enabled for specific
      # VexiEmailDomain actors; enabling globally would block all codespace creates.
      exclusion_list << :codespaces_block_email_domain
      # Feature gate for email domain blocking — disabled by default.
      exclusion_list << :codespaces_email_domain_blocking_enabled

      # We don't want these to be enabled for all users by default
      # before it getting introduced first to prevent a situation
      # where we cannot opt-out a user because it has already been enabled for everyone!
      exclusion_list << :codespaces_developer
      exclusion_list << :codespaces_per_user_sales_demo_limit
      # Codespaces regional circuit breakers
      Codespaces::VscsServiceStamp.public.each do |stamp|
        target_suffix = stamp.vscs_target == :production ? "" : "_#{stamp.vscs_target}"
        exclusion_list << "codespaces_region_override_rejection_#{stamp.region.id.downcase}".to_sym
        exclusion_list << "codespaces_region_rejecting_creates_#{stamp.region.id.downcase}#{target_suffix}".to_sym
        exclusion_list << "codespaces_region_rejecting_resumes_#{stamp.region.id.downcase}#{target_suffix}".to_sym
      end

      # Don't skip in test unless explicitly asked:
      exclusion_list << :active_job_skip_enqueue

      # Code scanning circuit breaker
      exclusion_list << :disable_code_scanning
      # Code quality circuit breaker
      exclusion_list << :code_quality_disable
      # Code coverage circuit breaker
      exclusion_list << :disable_code_coverage

      # Code scanning sarif validation experiment
      # this feature flag is enabled for third party tool repositories where we want to vet
      # the SARIF they produce.
      # we dont ever want this turned on for everyone as it would be confusing for customers to see errors
      # for tools they did not create.
      exclusion_list << :code_scanning_validate_sarif

      # Dependency Submission circuit breaker
      exclusion_list << :dependency_graph_snapshots_rate_limit_circuit_breaker
      # Dependency SBOM circuit breaker
      exclusion_list << :dependency_graph_sbom_rate_limit_circuit_breaker

      # React SSR circuit breaker
      exclusion_list << :disable_react_ssr

      # Long-lived Merge Queue flags
      exclusion_list << :merge_queue_deploy_then_merge
      exclusion_list << :merge_queue_emergency_shut_off

      # Merge Commit Request architecture flags
      exclusion_list << :disable_merge_commit_create_commits_jobs

      # If we default to the primary DB then we're missing coverage on tests that execute code behind a feature
      # flag that tries to write to a replica
      exclusion_list << :hydro_message_job_default_to_write_connection

      # Temporary flag for limiting anonymous requests to any endpoint
      exclusion_list << :endpoint_anon_blocked_actors

      # This will never be fully enabled in production, it's enabled for specific actors only
      # and used as an override only in case it's needed. Excluding here to avoid modifying
      # all existing tests that go through the caching path and test this rollout mode.
      exclusion_list << :remote_cache_return_source_value_with_extended_telemetry_for_cache_key_name

      # Same as above for remote_cache_return_source_value_with_extended_telemetry_for_cache_key_name,
      # but used for disabling caching for specific cache key names.
      exclusion_list << :remote_cache_disable_for_cache_key_name

      # Same as above, but used for disabling caching for specific sites.
      exclusion_list << :remote_cache_disable_for_site

      # Temporary flag for blocking all requests from specific IP addresses via GLB abuse blocking
      exclusion_list << :dotcom_web_blocked_ip_addresses

      # To artificially sunset deprecated GraphQL fields, we generate a feature flag
      # that acts like a switch to turn off a batch of fields every quarter
      # Since these flags are time sensitive, it often leads to a broken master.
      # We don't want to couple tests to time anyways, and we also don't want to have
      # to remove tests for deprecated fields right away. So here we exclude these flags:
      Platform::Schema.upcoming_changes.switch_flags.each do |sunset_flag|
        exclusion_list << sunset_flag
      end

      # Elasticsearch semantic indexing issues demo for POC
      # This requires ES 8.17 which is not available in our test environment yet
      exclusion_list << :elasticsearch_semantic_indexing_issues

      # exclusion list for the tier FF GlobalPercentThrottler
      # If these flags are enabled in tests, it will cause endpoints to always be throttled
      # and will cause tests to fail.
      exclusion_list << :api_platform_endpoint_throttler_enabled
      exclusion_list << :api_platform_endpoint_throttler_allow_no_traffic_routes
      exclusion_list << :api_platform_endpoint_throttler_allow_minimal_traffic_routes
      exclusion_list << :api_platform_endpoint_throttler_allow_low_traffic_routes
      exclusion_list << :api_platform_endpoint_throttler_allow_medium_traffic_routes
      exclusion_list << :api_platform_endpoint_throttler_allow_high_traffic_routes
      exclusion_list << :api_platform_endpoint_throttler_allow_maximum_traffic_routes

      # The following flags are only to be enabled for testing the Advanced Security CanProceedWithUsage
      # integration. Once we verify changes, we'll remove these.
      exclusion_list << :simulate_cs_locked_metered_usage
      exclusion_list << :simulate_sp_locked_metered_usage
      exclusion_list << :simulate_ghas_locked_metered_usage

      # Turning off since this is still an experiment
      exclusion_list << :pages_deploy_flow

      # This is only used to facilitate dev exploration of replacing rails layouts with a React-rendered app shell.
      # Will never be shipped in its current form or with this feature flag.
      exclusion_list << :force_react_app_shell

      # Temporary exclusion as the migration is still in early development
      # To be removed once github/global-navigation#114 is completed
      exclusion_list << :global_nav_react

      # Turn off the Copilot impact insights sidebar while the new navigation
      # group is still rolling out; TEST_ALL_FEATURES otherwise enables it and
      # breaks existing enterprise sidebar expectations across the suite.
      exclusion_list << :glc_copilot_metrics_v2

      # Turning off since this affects nearly all integration tests and will be off except for specific short-term cases
      exclusion_list << :rate_limited_request_anon_ip_allowlist

      # exercise the cache in tests, skip duplicate downstream requests
      exclusion_list << :remote_cache_configs_single_shadow_mode
      exclusion_list << :remote_cache_configs_batch_shadow_mode

      # This is for getting logging data on config data usage and doesn't need to be exercised in tests
      exclusion_list << :configsd_read_tracking

      # Turn off social compare repository list partitioning because early development
      # feature flag is only enabled for staff users controlling the experiment
      exclusion_list << :partitioning_social_compare_repository_list

      # billingcore experiment depends on billingd service which is not available in CI
      exclusion_list << :copilot_billing_check_experiment

      # complianced experiment depends on the complianced service which is not available in CI
      exclusion_list << :copilot_complianced_trade_experiment

      # billingd CustomersAPI experiment depends on billingd service which is not available in CI
      exclusion_list << :copilot_customer_ids_via_billingd

      # Turn off the new code view sidebar as it's still in early development and is failing the all-features-e2e tests
      # remove once the github-ui code is in place to properly render the React version
      exclusion_list << :react_data_router_code_view_sidebar

      # Turn off tree_file_list via Spokes API since there is a bug in `git ls-tree`
      exclusion_list << :tree_file_list_spokes_api

      # Memex Mission Control kill switch — disables all CAPI task calls.
      # Intended for incident response; excluded here so TEST_ALL_FEATURES doesn't
      # inadvertently disable agent task loading in tests.
      exclusion_list << :memex_disable_mission_control

      # Memex Mission Control aggressive timeout — switches to tighter timeouts.
      # Intended for incident response; excluded here so tests use default timeouts.
      exclusion_list << :memex_mission_control_aggressive_timeout

      # Turn off the new code view React header as it's still in early development
      # remove once the github-ui code is in place to properly render the React version
      exclusion_list << :code_view_react_header

      # Turn off the React marketing footer until tests are written for the new
      # render path; without this, TEST_ALL_FEATURES makes site.html.erb render
      # `render_react_partial "marketing-footer"`, which calls helpers.client_env
      # and SemanticLogger from React::SsrRenderer in environments where SSR
      # isn't available, breaking unrelated tests across many packages.
      exclusion_list << :site_marketing_footer_react

      # Turn off the React marketing header until tests are written for the new
      # render path; without this, TEST_ALL_FEATURES makes _marketing_header.html.erb
      # render `render_react_partial "marketing-header"` instead of the ERB markup,
      # which removes the server-rendered sign-in/login links and popover that many
      # logged-out tests assert on across the suite.
      exclusion_list << :site_marketing_header_react

      # Turn off the ui_route_code_view flag as the UI service is not available in CI
      exclusion_list << :ui_route_code_view

      # inavailability-incident-4314, to be removed after the incident is resolved and tests are fixed
      exclusion_list << :hydro_skip_issue_comment_id_too_big

      # Operational safety valve to shed anonymous search load during incidents.
      # Enabling this in tests would cause all anonymous search queries to be rejected,
      # breaking tests that expect search to function for unauthenticated users.
      exclusion_list << :load_shed_anonymous_search_queries

      # Per-query-type variant of the anonymous search load shedding valve. It is
      # only meant to be enabled for specific query-type actors (e.g.
      # "code_query"); enabling it globally (as TEST_ALL_FEATURES would) sheds
      # every anonymous search query, breaking tests that expect search to
      # function for unauthenticated users.
      exclusion_list << :load_shed_anonymous_search_queries_by_type

      # Kill switch to hide the GitHub Models UI in repositories.
      # Enabling this in tests would cause all models controller actions to 404,
      # breaking tests that expect the models tab to render.
      exclusion_list << :hide_github_models_ui

      # Deprecation flag to hide GitHub Models for users who have never configured billing.
      # Enabling this in tests would 404 models settings for new/unconfigured entities,
      # breaking tests that don't explicitly set up models billing configuration.
      exclusion_list << :models_deprecation_hide_new_users

      # Per-PR kill switch — meant to be enabled only for specific PullRequest
      # actors. Enabling globally would hide ALL pull requests from all users,
      # breaking any test that accesses a PR via web, API, or GraphQL.
      exclusion_list << :pull_request_kill_switch

      # Gradual-rollout flag that moves Team::Destruction::DestroyOperation into a
      # background orchestration (DestroyTeamOrchestration). Forcing it on under
      # TEST_ALL_FEATURES would make Team#destroy enqueue the async path, so existing
      # team-destruction tests that assert immediate cleanup would only observe a
      # queued job. Keep its real default (OFF) so those tests run the sync path.
      exclusion_list << :teams_destruction_job

      exclusion_list
    end
  end
end
