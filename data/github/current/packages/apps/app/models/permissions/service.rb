# typed: true
# frozen_string_literal: true

module Permissions

  class Service

    class EntryPoint

      # TODO: remove me as part of https://github.com/github/ecosystem-apps/issues/3954
      UNKNOWN = :unknown

      # This class represents the start of the code path that led to
      # initializing an operation on the `permissions` table. We use these
      # objects to store metadata about these entrypoints so we can surface
      # that information to our instrumentation systems. This helps us more
      # easily troubleshoot problematic access patterns on the permissions
      # cluster.
      #
      # All entry points should be registered in the `KNOWN_ENTRY_POINTS`
      # array after being approved by the Ecosystem Apps team.
      #
      # Eventually we will replace all `unknown` entry points so that our
      # instrumentation picture is complete, at which time providing an
      # unregistered or `nil` entry point argument will raise an error.

      class UnregisteredEntryPointError < ArgumentError; end

      # Please only modify these constants after consulting with the Ecosystem Apps
      # team via our repo: https://github.com/github/ecosystem-apps. Thanks!
      KNOWN_GRANT_ENTRY_POINTS = [
        :actions_controller_enable,
        :automatic_app_installation_handler_button_clicked,
        :automatic_app_installation_handler_dependabot_repository_access_updated,
        :automatic_app_installation_handler_dependency_graph_initialized,
        :automatic_app_installation_handler_dependency_update_requested,
        :automatic_app_installation_handler_file_added,
        :automatic_app_installation_handler_oauth_code_exchanged,
        :automatic_app_installation_handler_page_build,
        :automatic_app_installation_handler_pending_dependabot_installation_requested,
        :automatic_app_installation_handler_security_updates_initialized,
        :automatic_app_installation_handler_team_sync_enabled,
        :automatic_app_installation_handler_user_created,

        :business_enterprise_installations_controller_create,
        :business_organization_membership_update_private_search_on_orgs,

        :codespaces_commands_create_prebuild_template_dynamic_workflow,

        :codespaces_controller_create,
        :codespaces_controller_export,
        :codespaces_controller_show,

        :codespaces_subscribers_org_codespaces_disabled_event,
        :codespaces_subscribers_org_repo_owned_codespaces_disabled_event,

        :copilot_chat_tokens_controller_create,
        :copilot_diff_summary_repository_completions_controller_create,

        :device_authorization_controller_authorize,

        :edit_repositories_copilot_code_guidelines_sample_code_generations_controller_create,

        :git_src_migrator_run_dynamic_workflow,

        :graphql_api_create_repository_mutation,
        :graphql_api_clone_template_repository_mutation,

        :enterprise_installation_feature_updater,

        :hook_delivery_install_actions_app_and_queue_event,

        :integration_installation_controller_create,
        :integration_installation_controller_update,
        :integration_installation_controller_update_installation,
        :integration_installation_controller_update_permissions,
        :integration_installation_controller_build_access_after_installation,
        :integration_installation_controller_render_setup_redirect_create,
        :integration_installation_controller_render_setup_redirect_update,

        :manage_integrations_controller_grant,

        :orgs_codespaces_settings_controller_update_trusted_repositories_access,
        :orgs_permissions_integration_controller_grant,
        :organization_onboard_demo_repository_setup,

        :pages_builder_github_app_token,
        :page_publish_actions_run_dynamic_workflow,
        :personal_access_tokens_controller_create,
        :personal_access_tokens_grant_requests_controller_create,

        :repository_actions_settings_controller_setup_actions_app,
        :repository_actions_settings_controller_setup_actions_app_on_policy_change,
        :repositories_controller_install_selected_marketplace_apps,
        :registry_two_package_settings_controller_bulk_add_codespaces_access,
        :registry_two_package_settings_controller_add_codespaces_access,
        :registry_two_package_settings_controller_remove_codespaces_access,

        :rest_api_codespaces_create_for_authenticated_user,
        :rest_api_codespaces_create_with_pr_for_authenticated_user,
        :rest_api_codespaces_create_with_repo_for_authenticated_user,
        :rest_api_codespaces_private_mint_repository_token,
        :rest_api_codespaces_start_for_authenticated_user,
        :rest_api_create_registration_token_for_repo_runners,
        :rest_api_create_repo_for_authenticated_user,
        :rest_api_create_repo_for_organization,
        :rest_api_clone_repo_from_template,
        :rest_api_integrations_create_installation_access_token,
        :rest_api_integrations_create_permissionless_installation_access_token_internal,
        :rest_api_set_workflow_actions_for_repository_enable_actions_app,
        :rest_api_trigger_actions_dynamic_workflow,
        :rest_api_trigger_actions_dynamic_workflow_for_immutable_actions_migration,
        :rest_api_integrations_generate_site_scoped_token,
        :rest_api_add_repo_to_installation_for_authenticated_user,
        :rest_api_create_scoped_user_to_server_token,
        :rest_api_vscs_internal_fork_repo,
        :rest_api_codespaces_public_export,
        :rest_api_vscs_internal_prebuilds_post,
        :rest_api_enterprise_apps_change_installation_repository_access_selection,
        :rest_api_enterprise_apps_create_installation,
        :rest_api_enterprise_apps_grant_repository_access_to_installation,
        :rest_api_enterprise_apps_remove_repository_access_to_installation,

        :script_actions_queue_codespaces_dynamic_run,
        :script_actions_queue_dependabot_dynamic_run,
        :script_create_dependabot_example_vulnerable_repo,
        :script_generate_docs_payloads,

        :settings_enterprise_installations_controller_create,
        :seeds_objects_integrations_install,
        :seeds_runners_actions_create_and_install_github_app,
        :seeds_runners_gate_requests_create_actions_app,
        :seeds_runners_hyperlist_web_create_actions_app,
        :seeds_runners_repos_create_and_install_actions_app,
        :settings_codespaces_controller_update_trusted_repositories_access,
        :step_stacks_dispatch_workflow_enable_actions_app,

        :stream_processor_registry_metadata_repository_access_removal,

        :transfer_repository_orchestration_reinstall_integrations,
        :transfer_repository_orchestration_remove_installations,
        :twirp_api_registry_metadata_repo_api_handler,
        :twirp_api_classroom_integration_api_handler,
        :twirp_api_classroom_repositories_create_clone_api_handler,
        :twirp_api_classroom_repositories_create_repo_from_template_api_handler,
        :twirp_api_classroom_repositories_fork_api_handler,
        :twirp_api_copilot_agent_handler,
        :twirp_api_pages_job_secrets_provider,
        :twirp_api_internal_twirp_actions_core_v1_job_secrets_provider_codespaces_job_secrets_provider,
        :twirp_api_registry_metadata_repo_api_handler_remove_permissions_for_repository_job_remove_bulk,
        :twirp_api_registry_metadata_repo_api_handler_remove_permissions_for_repository_job_remove_access,

        :upgrade_integration_installation_version_job_auto_upgrade,

        :codespaces_command_publish_to_repository,

        :variant_analysis_actions_helper_run_dynamic_workflow,
      ]

      KNOWN_UPDATE_ENTRY_POINTS = [
        :oauth_controller_access_token,

        :personal_access_token_requests_controller_approve,
        :personal_access_token_requests_controller_bulk_approve,
        :personal_access_tokens_grant_requests_controller_create_auto_approve,

        :rest_api_integrations_installation_access_tokens,
        :rest_api_orgs_review_pat_grant_request,
        :rest_api_orgs_review_pat_grant_requests_in_bulk,
        :rest_api_remove_repo_from_installation_for_authenticated_user,

        :sync_scoped_installations_for_oauth_accesses_transition_downgrade,
      ]

      KNOWN_REVOKE_ENTRY_POINTS = [
        :branch_protection_rules_controller_create,
        :branch_protection_rules_controller_destroy,
        :branch_protection_rules_controller_update,
        :branches_controller_update,
        :cleanup_expired_permissions_job,
        :codespaces_subscribers_user_logout_event,
        :enterprise_installations_controller_upgrade_confirm,
        :graphql_api_create_branch_protection_rule_mutation,
        :graphql_api_branch_protection_rule_delete_mutation,
        :graphql_api_branch_protection_rule_modify_mutation,
        :graphql_api_update_branch_protection_rule_mutation,
        :hydro_message_handler_repo_removed_from_installations,
        :integration_transfers_controller_accept_finish_transfer,
        :integrations_controller_revoke_all_tokens,
        :manage_integrations_controller_revoke,
        :manage_integrations_revoke_job,
        :oauth_applications_controller_revoke_all_tokens,
        :oauth_authorizations_controller_destroy,
        :oauth_authorizations_controller_report,
        :oauth_authorizations_controller_revoke_all,
        :oauth_tokens_controller_destroy,
        :orgs_permissions_integration_controller_revoke,
        :protected_branch_importer,
        :public_key_destroy_callback,
        :remove_expired_oauth_job,
        :rest_api_admin_tokens_delete_token,
        :rest_api_applications_delete_oauth_access_token,
        :rest_api_applications_delete_oauth_authorization,
        :rest_api_authorizations_delete_authorization,
        :rest_api_branch_protection_delete,
        :rest_api_grants_delete_grant,
        :rest_api_repository_branch_rename,
        :rest_api_repository_protected_branch_enable,
        :rest_api_repository_protected_branch_admin_enforcement_delete,
        :rest_api_repository_protected_branch_admin_enforcement_update,
        :rest_api_repository_protected_branch_pull_request_review_enforcement_delete,
        :rest_api_repository_protected_branch_pull_request_review_enforcement_update,
        :rest_api_repository_protected_branch_push_restriction_app_list_add,
        :rest_api_repository_protected_branch_push_restriction_app_list_delete,
        :rest_api_repository_protected_branch_push_restriction_app_list_update,
        :rest_api_repository_protected_branch_push_restriction_disable,
        :rest_api_repository_protected_branch_push_restriction_team_list_add,
        :rest_api_repository_protected_branch_push_restriction_team_list_delete,
        :rest_api_repository_protected_branch_push_restriction_team_list_update,
        :rest_api_repository_protected_branch_push_restriction_user_list_add,
        :rest_api_repository_protected_branch_push_restriction_user_list_delete,
        :rest_api_repository_protected_branch_push_restriction_user_list_update,
        :rest_api_repository_protected_branch_required_status_check_context_add,
        :rest_api_repository_protected_branch_required_status_check_context_delete,
        :rest_api_repository_protected_branch_required_status_check_context_replace,
        :rest_api_repository_protected_branch_required_status_check_disable,
        :rest_api_repository_protected_branch_required_status_check_update,
        :rest_api_repository_protected_branch_required_signatures_disable,
        :rest_api_repository_protected_branch_required_signatures_enable,
        :script_seed_repo_for_code_scanning_development,
        :sessions_controller_mobile_revoke,
        :stacks_step_protect_branch,
        :stafftools_authorizations_controller_destroy,
        :stafftools_oauth_tokens_controller_destroy,
        :sync_scoped_installations_for_oauth_accesses_transition_revoke,
        :transfer_repository_orchestration_programmatic_fine_grained_permissions,
        :twirp_api_secretscanning_oauth_access_revoke_oauth_access,
        :unknown_oauth_access_destroy_authorization,
        :unknown_oauth_authorization_clear_permissions,
        :unknown_protected_branch_clear_app_permissions,
        :unknown_protected_branch_save,
        :unknown_remove_oauth_user_tokens_background_job,
      ]

      # Separate array for entry points that are known to be used outside of the codebase.
      # In a separate collection to avoid PermissionsServiceEntryPoint linting errors.
      KNOWN_USED_ENTRY_POINTS = [
        # This should only be used when running one off commands as part of proxima setup.
        # If it seems like your usage of this entry_point may be more significant than a simple action, please ask first.
        :proxima_manual_setup
      ]

      KNOWN_TEST_ENTRY_POINTS = [
        # Test helpers
        :test_helper,
        :test_case
      ]

      KNOWN_ENTRY_POINTS =
        KNOWN_GRANT_ENTRY_POINTS +
        KNOWN_UPDATE_ENTRY_POINTS +
        KNOWN_REVOKE_ENTRY_POINTS +
        KNOWN_TEST_ENTRY_POINTS +
        KNOWN_USED_ENTRY_POINTS

      ACTOR_LEVEL_EVENT_KEY = "permissions.service.write_requested"

      VALID_ACTOR_TYPES = %w[
        IntegrationInstallation
        OauthAuthorization
        OrganizationProgrammaticAccessGrant
        ScopedIntegrationInstallation
        SiteScopedIntegrationInstallation
        User
      ].freeze

      METRIC_SUFFIXES = %w[
        insert_rows_requested
        update_rows_requested
        deleted_rows
      ].freeze

      def self.unknown
        new(:unknown)
      end

      def self.lookup(entry_point)
        return entry_point if entry_point.is_a?(Permissions::Service::EntryPoint)
        return unknown if entry_point.blank?

        known_entry_point = KNOWN_ENTRY_POINTS.find do |ep|
          ep == entry_point
        end

        return new(known_entry_point) if known_entry_point.present?

        error = UnregisteredEntryPointError.new("Please register the `#{entry_point}` entry point with the Ecosystem Apps team: https://aka.ms/permissions-write-tracking")
        if GitHub::AppEnvironment.production?
          Failbot.report(error)

          self.unknown
        else
          raise error
        end
      end

      # TODO: make entry_point required once unknown entry points are addressed
      # https://github.com/github/ecosystem-apps/issues/3954
      sig do
        params(
          entry_point: T.nilable(Symbol),
          actor: T.nilable(
            T.any(
              IntegrationInstallation,
              OauthAuthorization,
              OrganizationProgrammaticAccessGrant,
              ScopedIntegrationInstallation,
              SiteScopedIntegrationInstallation,
              User
            )
          ),
          target: T.nilable(T.any(Business, Organization, User)),
          actor_owner: T.nilable(T.any(Integration, Organization, UserProgrammaticAccess)),
          parent_installation: T.nilable(IntegrationInstallation),
          scope_type: Symbol
        ).returns(Permissions::Service::EntryPoint)
      end
      def self.build(entry_point, actor: nil, target: nil, actor_owner: nil, parent_installation: nil, scope_type: :SCOPE_TYPE_UNKNOWN)
        entry_point ||= Permissions::Service::EntryPoint.unknown.entry_point
        new(entry_point, target:, actor:, actor_owner:, parent_installation:, scope_type:)
      end

      def self.instrument(metric_suffix:, count: 1, entry_point: Permissions::Service::EntryPoint.unknown, success: true, rows: [])
        raise ArgumentError.new("invalid metric suffix: '#{metric_suffix}'") unless METRIC_SUFFIXES.include?(metric_suffix)

        entry_point = lookup(entry_point)
        tags = ["entry_point:#{entry_point.tag_name}"]
        tags << "success:false" unless !!success

        GitHub.dogstats.distribution(
          "permissions_service.#{metric_suffix}",
          count,
          tags: tags
        )

        if should_instrument_service_actor_level_metrics?(entry_point)
          Permissions::EntryPoint::ActorContext.instrument(metric_suffix, entry_point, rows, count)
        end
      end

      def self.should_instrument_service_actor_level_metrics?(entry_point)
        return false unless GitHub.flipper[:permissions_service_actor_level_metrics].enabled?

        KNOWN_ENTRY_POINTS.include?(entry_point.to_sym)
      end

      attr_reader :entry_point, :actor, :actor_owner, :parent_installation, :target, :scope_type

      sig do
        params(
          entry_point: Symbol,
          actor: T.nilable(
            T.any(
              IntegrationInstallation,
              OauthAuthorization,
              OrganizationProgrammaticAccessGrant,
              ScopedIntegrationInstallation,
              SiteScopedIntegrationInstallation,
              User
            )
          ),
          target: T.nilable(T.any(Business, Organization, User)),
          actor_owner: T.nilable(T.any(Integration, Organization, UserProgrammaticAccess)),
          parent_installation: T.nilable(IntegrationInstallation),
          scope_type: Symbol
        ).void
      end
      def initialize(entry_point, actor: nil, target: nil, actor_owner: nil, parent_installation: nil, scope_type: :SCOPE_TYPE_UNKNOWN)
        @target = target
        @actor = actor
        @actor_owner = actor_owner
        @entry_point = entry_point
        @parent_installation = parent_installation
        @scope_type = scope_type
      end

      def tag_name
        entry_point.to_s
      end

      def to_sym
        entry_point.to_sym
      end

      def to_s
        entry_point.to_s
      end
    end

    GRANT_PERMISSIONS_BATCH_SIZE  = 100
    REVOKE_PERMISSIONS_BATCH_SIZE = 100
    UPDATE_PERMISSIONS_BATCH_SIZE = 100

    ACTOR_CONTEXT_QUERY_STATS_KEY = "permissions.service.actor_context_query"

    PERMISSION_KEYS = %i(
      actor_id
      actor_type
      action
      subject_id
      subject_type
      priority
      parent_id
      created_at
      updated_at
      expires_at
    ).freeze

    def self.async_can?(actor, action, subject)
      ::Platform::Loaders::Permission.load(actor, subject).then do |max_action|
        if max_action
          max_action >= Permission.actions[action]
        else
          false
        end
      end
    end

    # TODO: This method should eventually be removed in favor of
    # .grant_permissions! as INSERT IGNORE can mask subtle bugs resulting in
    # missing permissions.
    def self.grant_permissions(rows = [], entry_point: Permissions::Service::EntryPoint.unknown, stats_key: nil)
      return if rows.empty?
      # TODO: This is a temporary measure to allow refactoring of the
      # ScopedIntegrationInstallation creators.
      # This allows callers to either pass:
      # 1) An Array of Arrays containing raw values for the INSERT statement
      # 2) An Array of Hashes containing ActiveRecord style values, also
      #    suitable for .grant_permissions!
      sanitized_rows = rows.map do |row|
        next row if row.is_a?(Array)
        expiry = row.fetch(:expires_at)
        expiry = nil if expiry == 0 # AR 0 doesn't work in raw SQL, sets date to unix epoch.
        [
          row.fetch(:actor_id),
          row.fetch(:actor_type),
          Permission.actions[row.fetch(:action)],
          row.fetch(:subject_id),
          row.fetch(:subject_type),
          Ability.priorities[:direct],
          0,
          GitHub::SQL::ArelLiterals::NOW,
          GitHub::SQL::ArelLiterals::NOW,
          expiry,
        ]
      end

      Permissions::Service::EntryPoint.instrument(
        metric_suffix: "insert_rows_requested",
        count: rows.size,
        entry_point: entry_point,
        rows: rows,
      )

      sanitized_rows.in_groups_of(GRANT_PERMISSIONS_BATCH_SIZE, false) do |batch_rows|
        ActiveRecord::Base.connected_to(role: :writing) do
          ApplicationRecord::Permissions.connection.insert(Arel.sql(<<-SQL, rows: Arel::Nodes::ValuesList.new(batch_rows)))
            INSERT IGNORE INTO permissions
            (actor_id, actor_type, action, subject_id, subject_type,
             priority, parent_id, created_at, updated_at, expires_at)
            :rows
          SQL
        end

        # TODO: Remove this. Histograms are not considered good practice
        # anymore. Eventually, this can be replaced with the `EntryPoint`
        # system.
        if stats_key
          GitHub.dogstats.histogram "permissions.granted.#{stats_key}", rows.size
        end
      end

      true
    end

    def self.grant_permissions!(rows = [], entry_point: Permissions::Service::EntryPoint.unknown, stats_key: nil)
      return if rows.empty?

      Permissions::Service::EntryPoint.instrument(
        metric_suffix: "insert_rows_requested",
        count: rows.size,
        entry_point: entry_point,
        rows: rows,
      )

      rows.in_groups_of(GRANT_PERMISSIONS_BATCH_SIZE, false) do |batch_row|
        ActiveRecord::Base.connected_to(role: :writing) do
          Permission.insert_all!(batch_row, returning: false)
        end

        if stats_key
          GitHub.dogstats.histogram "permissions.granted.#{stats_key}", batch_row.size
        end
      end
    end

    def self.update_action_for_permissions(actor_ids: [], actor_type:, subject_types: [], action:, entry_point: Permissions::Service::EntryPoint.unknown)
      return if actor_ids.empty? || subject_types.empty?

      if GitHub.flipper[:permissions_service_actor_level_metrics].enabled?
        entry_point = Permissions::Service::EntryPoint.lookup(entry_point)
        permissions = Permission
          .where(actor_id: actor_ids)
          .where(actor_type: actor_type)
          .where(subject_type: subject_types)

        Permissions::Service::EntryPoint.instrument(
          metric_suffix: "update_rows_requested",
          entry_point: entry_point,
          rows: permissions
        )

        throttle_writes_in_background_with_retry do
          # TODO [sorbet]: Remove this T.must after upgrading Sorbet.
          # It provides compatibility with future Sorbet/tapioca version where `in_batches` is not nilable.
          T.must(permissions
            .in_batches(of: ::Permissions::Service::UPDATE_PERMISSIONS_BATCH_SIZE))
            .update_all(action: Ability.actions[action])
        end
      else
        args = {
          actor_ids: actor_ids,
          actor_type: actor_type,
          subject_types: subject_types,
          action: Ability.actions[action],
        }

        ids = ApplicationRecord::Permissions.connection.select_rows(Arel.sql(<<-SQL, **args))
          SELECT id from permissions
          WHERE actor_id IN (:actor_ids)
          AND actor_type = :actor_type
          AND subject_type IN (:subject_types)
        SQL

        entry_point = Permissions::Service::EntryPoint.lookup(entry_point)
        Permissions::Service::EntryPoint.instrument(metric_suffix: "update_rows_requested", count: ids.flatten(1).size, entry_point: entry_point)

        ids.flatten(1).in_groups_of(UPDATE_PERMISSIONS_BATCH_SIZE, false) do |batched_ids|
          throttle_writes_in_background_with_retry do
            ApplicationRecord::Permissions.connection.update(Arel.sql(<<-SQL, ids: batched_ids, action: args[:action]))
              UPDATE permissions
              SET action = :action
              WHERE id IN (:ids)
            SQL
          end
        end
      end
    end

    def self.update_actor_id_and_actor_type_for_permissions(permissions:, actor_id:, actor_type:, timestamp:, entry_point: Permissions::Service::EntryPoint.unknown)
      entry_point = Permissions::Service::EntryPoint.lookup(entry_point)

      Permissions::Service::EntryPoint.instrument(
        metric_suffix: "update_rows_requested",
        entry_point: entry_point,
        rows: permissions
      )

      throttle_writes_in_background_with_retry do
        permissions
          .in_batches(of: ::Permissions::Service::UPDATE_PERMISSIONS_BATCH_SIZE)
          .update_all(actor_id: actor_id, actor_type: actor_type, updated_at: timestamp)
      end
    end

    def self.update_expires_at_for_permissions(permission_ids: nil, timestamp: nil, entry_point: Permissions::Service::EntryPoint.unknown)
      return unless timestamp.present?

      if GitHub.flipper[:permissions_service_actor_level_metrics].enabled?
        entry_point = Permissions::Service::EntryPoint.lookup(entry_point)
        permissions = Permission.where(id: permission_ids)

        Permissions::Service::EntryPoint.instrument(
          metric_suffix: "update_rows_requested",
          entry_point: entry_point,
          rows: permissions
        )
      else
        entry_point = Permissions::Service::EntryPoint.lookup(entry_point)
        Permissions::Service::EntryPoint.instrument(metric_suffix: "update_rows_requested", count: permission_ids.size, entry_point: entry_point)
      end

      Array(permission_ids).in_groups_of(::Permissions::Service::UPDATE_PERMISSIONS_BATCH_SIZE, false) do |batched_ids|
        throttle_writes_in_background_with_retry do
          ApplicationRecord::Permissions.connection.update(Arel.sql(<<-SQL, expires_at: timestamp.to_i, ids: batched_ids))
            UPDATE permissions
            SET expires_at = :expires_at
            WHERE id IN (:ids)
          SQL
        end
      end
    end

    def self.revoke_permissions(actor_id:, actor_type:, subject_id:, subject_type:, action:, priority:, entry_point: nil)
      args = {
        actor_id: actor_id,
        actor_type: actor_type,
        subject_id: subject_id,
        subject_type: subject_type,
        action: action,
        priority: priority,
      }

      instrumentation_args = {
        metric_suffix: "deleted_rows",
        entry_point: entry_point,
      }

      if GitHub.flipper[:permissions_service_actor_level_metrics].enabled?
        with_stats_for_actor_context_query(entry_point) do
          relation = Permission.where(args)
          instrumentation_args[:rows] = Permissions::EntryPoint::ActorContext.normalize_rows(relation)
        end
      end

      begin
        ActiveRecord::Base.connected_to(role: :writing) do
          deleted_count = ApplicationRecord::Permissions.connection.delete(Arel.sql(<<-SQL, **args))
            DELETE FROM permissions
            WHERE actor_id = :actor_id
            AND actor_type = :actor_type
            AND subject_id = :subject_id
            AND subject_type = :subject_type
            AND action = :action
            AND priority = :priority
          SQL
          instrumentation_args[:count] = deleted_count
          deleted_count
        end
      ensure
        Permissions::Service::EntryPoint.instrument(**instrumentation_args)
      end
    end

    sig { params(ids: T::Array[Integer], entry_point: T.any(Permissions::Service::EntryPoint, NilClass, Symbol)).void }
    def self.revoke_permissions_by_id(ids, entry_point: Permissions::Service::EntryPoint.unknown)
      return unless ids.any?

      instrumentation_args = {
        metric_suffix: "deleted_rows",
        entry_point: entry_point,
      }

      if GitHub.flipper[:permissions_service_actor_level_metrics].enabled?
        with_stats_for_actor_context_query(entry_point) do
          relation = Permission.where(id: ids)
          instrumentation_args[:rows] = Permissions::EntryPoint::ActorContext.normalize_rows(relation)
        end
      end

      begin
        deleted_count = 0
        ids.flatten(1).in_groups_of(REVOKE_PERMISSIONS_BATCH_SIZE, false) do |batched_ids|
          throttle_writes_in_background_with_retry do
            deleted_count += ApplicationRecord::Permissions.connection.delete(Arel.sql(<<-SQL, ids: batched_ids))
              DELETE FROM permissions
              WHERE id IN (:ids)
            SQL
          end
        end
        instrumentation_args[:count] = deleted_count
      ensure
        Permissions::Service::EntryPoint.instrument(**instrumentation_args)
      end
    end

    def self.revoke_permissions_granted_on_actors(actor_ids: [], actor_type:, subject_types: [], entry_point: Permissions::Service::EntryPoint.unknown)
      return if actor_ids.empty?

      sql = Arel.sql(<<-SQL, actor_ids: actor_ids, actor_type: actor_type)
        SELECT id FROM permissions
        WHERE actor_id IN (:actor_ids)
        AND actor_type = :actor_type
      SQL

      unless subject_types.empty?
        sql += Arel.sql(<<-SQL, subject_types: subject_types)
          AND subject_type IN (:subject_types)
        SQL
      end

      ids = ApplicationRecord::Permissions.connection.select_rows(sql)

      revoke_permissions_by_id(ids, entry_point: entry_point)
    end

    def self.revoke_permissions_granted_on_actor(actor_id:, actor_type:, subject_types: [], entry_point: Permissions::Service::EntryPoint.unknown)
      revoke_permissions_granted_on_actors(
        actor_ids: Array(actor_id), actor_type: actor_type, subject_types: subject_types, entry_point: entry_point
      )
    end

    def self.revoke_permissions_granted_on_subject(actor_id: nil, actor_type: nil, subject_id:, subject_types:, entry_point:)
      revoke_permissions_granted_on_subjects(
        actor_ids:      Array(actor_id),
        actor_type:    actor_type,
        subject_ids:   Array(subject_id),
        subject_types: Array(subject_types),
        entry_point: entry_point,
      )
    end

    def self.revoke_permissions_granted_on_subjects(actor_ids: [], actor_type: nil, subject_ids:, subject_types:, entry_point: Permissions::Service::EntryPoint.unknown)
      subject_ids = Array(subject_ids)
      return if subject_ids.empty?

      args = { subject_types: Array(subject_types) }
      return if args[:subject_types].empty?

      sql = <<-SQL
        DELETE FROM permissions
        WHERE subject_id IN (:subject_ids)
        AND subject_type IN (:subject_types)
      SQL

      filter_by_actor = actor_ids.any? && actor_type.present?

      if filter_by_actor
        sql += <<-SQL
          AND actor_id IN (:actor_ids)
          AND actor_type = :actor_type
        SQL

        args[:actor_ids]  = actor_ids
        args[:actor_type] = actor_type
      end

      instrumentation_args = {
        metric_suffix: "deleted_rows",
        entry_point: entry_point,
      }

      subject_ids.in_groups_of(REVOKE_PERMISSIONS_BATCH_SIZE, false) do |ids|
        args[:subject_ids] = ids

        if GitHub.flipper[:permissions_service_actor_level_metrics].enabled?
          with_stats_for_actor_context_query(entry_point) do
            relation = Permission.where(subject_id: ids, subject_type: args[:subject_types])
            relation = relation.where(actor_id: actor_ids, actor_type: actor_type) if filter_by_actor
            instrumentation_args[:rows] = Permissions::EntryPoint::ActorContext.normalize_rows(relation)
          end
        end

        begin
          deleted_count = 0
          throttle_writes_in_background_with_retry do
            deleted_count += ApplicationRecord::Permissions.connection.delete(Arel.sql(sql, **args))
          end
          instrumentation_args[:count] = deleted_count
        ensure
          Permissions::Service::EntryPoint.instrument(**instrumentation_args)
        end
      end
    end

    def self.actor_ids_granted_permission(actor_type:, subject_type:, subject_ids:, action:)
      args = {
        priority: Ability.priorities[:direct],
        actor_type: actor_type,
        subject_type: subject_type,
        subject_ids: Array(subject_ids),
        action: Array(action),
      }

      ApplicationRecord::Permissions.connection.select_values(Arel.sql(<<-SQL, **args))
        SELECT actor_id
        FROM permissions
        WHERE priority = :priority
        AND actor_type = :actor_type
        AND subject_type = :subject_type
        AND subject_id IN (:subject_ids)
        AND action IN (:action)
      SQL
    end

    def self.subject_ids_granted_permission(actor_ids:, actor_type:, subject_type:, action:)
      args = {
        priority: Ability.priorities[:direct],
        actor_ids: Array(actor_ids),
        actor_type: actor_type,
        subject_type: subject_type,
        action: Array(action),
      }

      ApplicationRecord::Permissions.connection.select_values(Arel.sql(<<-SQL, **args))
        SELECT subject_id
        FROM permissions
        WHERE priority = :priority
        AND actor_id IN (:actor_ids)
        AND actor_type = :actor_type
        AND subject_type = :subject_type
        AND action IN (:action)
      SQL
    end

    sig { params(actor_type: String, actor_id: Integer, offset_id: Integer, limit: Integer).returns(T::Array[Integer]) }
    def self.permission_ids_granted_on_actor_with_limit_and_offset(actor_type:, actor_id:, offset_id: 0, limit: GRANT_PERMISSIONS_BATCH_SIZE)
      args = {
        actor_type: actor_type,
        actor_id: actor_id,
        offset_id: offset_id,
        limit: Arel.sql(limit.to_s),
      }

      ApplicationRecord::Permissions.connection.select_values(Arel.sql(<<-SQL, **args))
        SELECT id
        FROM permissions
        WHERE
          actor_type = :actor_type
          AND actor_id = :actor_id
          AND id > :offset_id
        ORDER BY
          id ASC
        LIMIT
          :limit
      SQL
    end

    sig { params(timestamp: Time, offset_id: Integer, limit: Integer).returns(T::Array[Integer]) }
    def self.expired_permission_ids_with_limit_and_offset(timestamp:, offset_id:, limit:)
      Permission
        .where(Permission.arel_table[:expires_at].lt(timestamp.to_i))
        .where(Permission.arel_table[:id].gt(offset_id))
        .order(id: :asc)
        .limit(limit)
        .pluck(:id)
    end

    def self.has_direct_permission?(actor_id:, actor_type:, subject_type:, subject_ids:, action:)
      actor_ids_granted_permission(
        actor_type: actor_type,
        subject_type: subject_type,
        subject_ids: subject_ids,
        action: action,
      ).include?(actor_id)
    end

    sig { params(actor_id: Integer, actor_type: String, subject_types: T::Array[String], min_action: Symbol).returns(T::Boolean) }
    def self.installed_on_all_repositories?(actor_id:, actor_type:, subject_types:, min_action: :read)
      query = Permission.where(
        actor_id: actor_id,
        actor_type: actor_type,
        subject_type: subject_types
      )

      if T.must(Permission.actions[min_action]) > T.must(Permission.actions[:read])
        query = query.where("action >= ?", Permission.actions[min_action])
      end

      query.exists?
    end

    # Public: grant a Permission of action between actor and subject
    #
    # actor    - An IntegrationInstallation
    # subject  - Resource permission is granting access to
    # action   - Action available to actor on resource
    #
    # Returns nil.
    def self.grant_app_permission(actor:, subject:, action:, entry_point: Permissions::Service::EntryPoint.unknown)
      attributes = app_attributes(actor: actor, subject: subject, action: action)
      grant_permissions([attributes], entry_point: entry_point)
    end

    # Public: delete direct app permissions in the Collab cluster.
    # Use this method to wrap calls to delete FGP abilities records for
    # IntegrationInstallations.
    #
    # permissions - Array of Ability records.
    #
    # Returns nil.
    def self.delete_app_permissions(permissions:)
      ApplicationRecord::Permissions.transaction do
        permissions.each do |permission|
          Permissions::Service.revoke_permissions(
            actor_id: permission.actor_id,
            actor_type: permission.actor_type,
            subject_id: permission.subject_id,
            subject_type: permission.subject_type,
            action: Ability.actions[permission.action],
            priority: Ability.priorities[permission.priority],
          )
        end
      end
    end

    # Public: builds an array of values representing a SQL row for insertion
    # into the permissions table, for a GitHub App.
    #
    # Returns an Array.
    def self.app_attributes(actor:, subject:, action:, priority: nil, expires_at: nil)
      [
        actor.id,
        actor.ability_type,
        Ability.actions[action],
        subject.ability_id,
        subject.ability_type,
        Ability.priorities[priority || :direct],
        0, # No need for a parent ID that points to an actual ability record.
        GitHub::SQL::ArelLiterals::NOW,
        GitHub::SQL::ArelLiterals::NOW,
        expires_at,
      ]
    end

    # Public: builds a hash of attributes representing a SQL row for insertion into
    # the permissions table, for a type of GitHub App
    # (Scoped|SiteScoped)IntegrationInstallation.
    #
    # Returns a Hash.
    def self.installation_attributes_hash(actor:, subject:, action:, priority: :direct, expires_at: nil)
      timestamp = Time.zone.now
      expires_at = expires_at.to_i if expires_at.present?

      {
        actor_id: actor.ability_id,
        actor_type: actor.ability_type,
        action: action,
        subject_id: subject.ability_id,
        subject_type: subject.ability_type,
        priority: priority,
        parent_id: 0,
        created_at: timestamp,
        updated_at: timestamp,
        expires_at: expires_at,
      }
    end

    def self.installation_attributes_from_values(values)
      return {} if values.nil? || values.size != PERMISSION_KEYS.size

      hash = Hash[PERMISSION_KEYS.zip(values)]

      # Overwrite SQL timestamp with Time objects for ActiveRecord
      now = Time.zone.now
      hash[:created_at] = now
      hash[:updated_at] = now
      hash[:expires_at] = nil if hash[:expires_at] == GitHub::SQL::NULL

      hash
    end

    def self.throttle_writes_in_background_with_retry(&block)
      return yield if GitHub.foreground?
      ApplicationRecord::Permissions.throttle_writes_with_retry(max_retry_count: 5, &block)
    end

    def self.with_stats_for_actor_context_query(entry_point, &block)
      tags = [
        "entry_point:#{entry_point}",
        "background:#{!GitHub.foreground?}",
      ]

      GitHub.dogstats.distribution_time(ACTOR_CONTEXT_QUERY_STATS_KEY, tags: tags) do
        ActiveRecord::Base.connected_to(role: :reading) do
          yield
        end
      end
    end
  end
end
