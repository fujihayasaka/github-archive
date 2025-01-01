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

      exclusion_list << :registry_disable
      exclusion_list << :registry_alpha_disabled

      # Circuit breaker kill switch for creating codespaces - we don't want
      # this enabled during tests that attempt to create codespaces.
      exclusion_list << :disable_codespace_creation
      # Kill switch to disable issues react for debugging purposes
      exclusion_list << :issues_react_disabled

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
      # Code scanning special licensing restriction
      exclusion_list << :code_scanning_enterprise_disabled

      # Code scanning sarif validation experiment
      # this feature flag is enabled for third party tool repositories where we want to vet
      # the SARIF they produce.
      # we dont ever want this turned on for everyone as it would be confusing for customers to see errors
      # for tools they did not create.
      exclusion_list << :code_scanning_validate_sarif

      # Dependency Submission circuit breaker
      exclusion_list << :dependency_graph_snapshots_rate_limit_circuit_breaker

      # React SSR circuit breaker
      exclusion_list << :disable_react_ssr

      # Long-lived Merge Queue flags
      exclusion_list << :merge_queue_deploy_then_merge
      exclusion_list << :merge_queue_emergency_shut_off

      # Merge Commit Request architecture flags
      exclusion_list << :disable_mcr_engine
      exclusion_list << :disable_merge_commit_create_commits_jobs

      # If we default to the primary DB then we're missing coverage on tests that execute code behind a feature
      # flag that tries to write to a replica
      exclusion_list << :hydro_message_job_default_to_write_connection

      # Notifyd is temporarily testing a new maintenance API for jobs.
      exclusion_list << :notifyd_maintenance_delete_repository
      exclusion_list << :notifyd_maintenance_delete_repository_for_users
      exclusion_list << :notifyd_maintenance_delete_user
      exclusion_list << :notifyd_maintenance_delete_user_repositories

      # This feature flag is an experimental flag designed to reduce the number
      # of queries necessary to load the layout. This should be explicitly
      # enabled in tests attempting to count the number of queries.
      exclusion_list << :magic_shell_caching
      exclusion_list << :navbar_hits
      exclusion_list << :navbar_hits_details

      # Temporary flag for limiting anonymous requests to any endpoint
      exclusion_list << :endpoint_anon_blocked_actors

      # Temporary flag for blocking all requests from specific IP addresses via GLB abuse blocking
      exclusion_list << :dotcom_web_blocked_ip_addresses

      # We turned off this feature flag to prevent having over 100 failing tests that would need manual updates.
      # This flag was created to limit access to all PATs made without proper onboarding during the period when 'patsv2_default_opt_in' is active.
      # We’ll use this flag only if we decide to disable 'patsv2_default_opt_in'.
      exclusion_list << :require_onboarding_for_pat_activation

      # Turning off since this is still an experiment
      exclusion_list << :ui_deploys

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

      # We don't want to run the tests with release attestations enabled
      exclusion_list << :attested_releases

      # exclustion list for the tier FF GlobalPercentThrottler
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

      exclusion_list
    end
  end
end
