# typed: strict
# frozen_string_literal: true

module FeatureFlag
  class AllFeatures
    extend T::Sig

    sig { returns(T::Array[Symbol]) }
    def self.exclusion_list
      exclusion_list = T.let([], T::Array[Symbol])

      exclusion_list << :registry_disable
      exclusion_list << :registry_alpha_disabled

      # Circuit breaker kill switch for creating codespaces - we don't want
      # this enabled during tests that attempt to create codespaces.
      exclusion_list << :disable_codespace_creation

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
      # Alloy experiment with manifest
      exclusion_list << :use_alloy_manifest

      # Long-lived Merge Queue flags
      exclusion_list << :merge_queue_deploy_then_merge
      exclusion_list << :merge_queue_emergency_shut_off

      # This flag is used to easily disable turbo experiments, making changes to turbo easier.
      exclusion_list << :turbo_experiment
      exclusion_list << :turbo_experiment_risky

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

      # To artificially sunset deprecated GraphQL fields, we generate a feature flag
      # that acts like a switch to turn off a batch of fields every quarter
      # Since these flags are time sensitive, it often leads to a broken master.
      # We don't want to couple tests to time anyways, and we also don't want to have
      # to remove tests for deprecated fields right away. So here we exclude these flags:
      Platform::Schema.upcoming_changes.switch_flags.each do |sunset_flag|
        exclusion_list << sunset_flag
      end

      exclusion_list
    end
  end
end
