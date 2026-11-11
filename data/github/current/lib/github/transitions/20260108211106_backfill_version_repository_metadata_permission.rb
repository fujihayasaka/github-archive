# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

module GitHub
  module Transitions
    class BackfillVersionRepositoryMetadataPermission < Base
      include GitHub::Memoizer

      class IntegrationVersionForTransition < ApplicationRecord::Domain::Integrations
        self.table_name = :integration_versions
      end

      class PermissionForTransition < ApplicationRecord::Permissions
        self.table_name = :permissions
      end

      class DefaultIntegrationPermissionForTransition < ApplicationRecord::Domain::Users
        self.table_name = :default_integration_permissions
      end

      class IntegrationInstallationForTransition < ApplicationRecord::Domain::Integrations
        self.table_name = :integration_installations
      end

      PERMISSION_READ_ACTION = 0
      PERMISSION_DIRECT_PRIORITY = 1
      DEFAULT_INTEGRATION_PERMISSION_READ_ACTION = 0
      DEFAULT_INTEGRATION_PERMISSION_ACTIONS = T.let({
        DEFAULT_INTEGRATION_PERMISSION_READ_ACTION => :read,
        1 => :write,
        2 => :admin,
      }.freeze, T::Hash[Integer, Symbol])
      BATCH_SIZE = T.let(GitHub.enterprise? ? 10000 : 100, Integer)
      REPO_SPECIFIC_METADATA_SUBJECT_TYPE = "Repository/metadata"
      ALL_USER_REPO_METADATA_SUBJECT_TYPE = "User/repositories/metadata"
      DOTCOM_INTEGRATION_VERSION_ID_CUTOFF = 338581
      DOTCOM_REPO_SUBJECT_TYPES = %w(actions actions_variables administration app_config artifact_metadata
        attestations checks codespaces codespaces_lifecycle_admin codespaces_metadata codespaces_secrets contents
        copilot_requests dependabot_secrets deployments discussions environments issues merge_queues metadata models
        organization_packages packages pages pull_requests pull_requests_comment_only_reviews pull_requests_from_forks
        repo_secret_scanning_dismissal_requests repository_advisories repository_announcement_banners
        repository_custom_properties repository_hooks repository_projects secret_scanning_alerts
        secret_scanning_bypass_requests secrets security_events single_file statuses vulnerability_alerts
        workflows).freeze
      GHES_REPO_SUBJECT_TYPES = T.let((DOTCOM_REPO_SUBJECT_TYPES + %w(repository_pre_receive_hooks)).freeze,
        T::Array[String])
      DOTCOM_REPO_TYPE_PREFIXED_SUBJECT_TYPES = %w(User/repositories/actions User/repositories/actions_variables
        User/repositories/administration User/repositories/artifact_metadata User/repositories/attestations
        User/repositories/checks User/repositories/codespaces User/repositories/codespaces_lifecycle_admin
        User/repositories/codespaces_metadata User/repositories/codespaces_secrets User/repositories/contents
        User/repositories/copilot_requests User/repositories/dependabot_secrets User/repositories/deployments
        User/repositories/discussions User/repositories/environments User/repositories/issues
        User/repositories/merge_queues User/repositories/metadata User/repositories/models
        User/repositories/organization_packages User/repositories/packages User/repositories/pages
        User/repositories/pull_requests User/repositories/pull_requests_comment_only_reviews
        User/repositories/pull_requests_from_forks User/repositories/repo_secret_scanning_dismissal_requests
        User/repositories/repository_advisories User/repositories/repository_announcement_banners
        User/repositories/repository_custom_properties User/repositories/repository_hooks
        User/repositories/repository_projects User/repositories/secret_scanning_alerts
        User/repositories/secret_scanning_bypass_requests User/repositories/secrets User/repositories/security_events
        User/repositories/single_file User/repositories/statuses User/repositories/vulnerability_alerts
        User/repositories/workflows).freeze
      GHES_REPO_TYPE_PREFIXED_SUBJECT_TYPES = T.let(
        (DOTCOM_REPO_TYPE_PREFIXED_SUBJECT_TYPES + %w(User/repositories/repository_pre_receive_hooks)).freeze,
        T::Array[String]
      )

      sig { returns String }
      def self.iterator_conditions
        if GitHub.enterprise?
          "id IS NOT NULL"
        else
          # See https://github.com/github/ecosystem-apps/issues/8340#issuecomment-3855243235 for reasoning about
          # why we only care about integration versions before this one.
          "id <= #{DOTCOM_INTEGRATION_VERSION_ID_CUTOFF}"
        end
      end

      # Configure iterator to iterate over all integration versions
      iterate_over :database_table, params: {
        model_class: IntegrationVersionForTransition,
        conditions: iterator_conditions,
        columns: %i[id integration_id],
      }

      sig { override.void }
      def after_initialize
        @backfilled_version_ids = T.let(Set.new, T.nilable(T::Set[Integer]))
        @total_default_perms_backfilled = T.let(0, T.nilable(Integer))
        @total_perms_backfilled = T.let(0, T.nilable(Integer))
        @total_default_perms_failed = T.let(0, T.nilable(Integer))
        @total_perms_failed = T.let(0, T.nilable(Integer))
        @installation_start_id = T.let(arguments[:installation_start_id]&.to_i, T.nilable(Integer))
        @installation_end_id = T.let(arguments[:installation_end_id]&.to_i, T.nilable(Integer))
      end

      sig { returns T.nilable(Integer) }
      attr_reader :total_default_perms_backfilled, :total_default_perms_failed, :total_perms_backfilled,
        :total_perms_failed, :installation_start_id, :installation_end_id

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        log_about_given_arguments

        version_ids = items.keys.map(&:to_i)
        log_process_version_batch(version_ids)

        # Load data about the whole batch so we avoid n+1 queries:
        default_permissions_by_version_id = load_default_permissions(version_ids)

        items.each do |raw_version_id, data|
          version_id = raw_version_id.to_i
          process_version(
            version_id: version_id,
            integration_id: data[:integration_id].to_i,
            default_permissions: default_permissions_by_version_id[version_id] || {},
          )
        end

        log_backfilled_version_batch(version_ids)
        log_batch_success_failure(version_ids)
      end

      private

      sig { returns T::Boolean }
      memoize def single_integration_version_targeted?
        start_id = arguments[:start_id]
        return false if start_id.nil?

        end_id = arguments[:end_id]
        return false if end_id.nil?

        start_id.to_i == end_id.to_i
      end

      sig { params(version_id: Integer, integration_id: Integer, default_permissions: T::Hash[String, Symbol]).void }
      def process_version(version_id:, integration_id:, default_permissions:)
        return true unless uses_repo_permissions?(version_id, default_permissions)

        if version_needs_backfill?(version_id, default_permissions)
          log("Version #{version_id} of integration #{integration_id} needs metadata permission backfill") if verbose?

          if create_default_integration_permission(version_id: version_id, integration_id: integration_id)
            @total_default_perms_backfilled = T.must(@total_default_perms_backfilled) + 1
            @backfilled_version_ids.add(version_id) if @backfilled_version_ids
          else
            @total_default_perms_failed = T.must(@total_default_perms_failed) + 1
          end
        end

        each_installations_batch_for(integration_id, version_id: version_id) do |installations|
          installation_ids_to_check_for_backfill =
            load_installation_ids_using_repo_permissions(installations.map(&:id))
          next if installation_ids_to_check_for_backfill.empty?

          installations_to_check_for_backfill = installations
            .select { |i| installation_ids_to_check_for_backfill.include?(i.id) }
          process_installations_batch(installations_to_check_for_backfill, integration_id)
        end
      end

      sig { params(version_id: Integer, default_permissions: T::Hash[String, Symbol]).returns(T::Boolean) }
      def version_needs_backfill?(version_id, default_permissions)
        if default_permissions.key?("metadata")
          log("Skipping default integration permission backfill for integration version #{version_id}: already has " \
            "metadata permission") if verbose?
          return false
        end

        true
      end

      sig { params(version_id: Integer, default_permissions: T::Hash[String, Symbol]).returns(T::Boolean) }
      def uses_repo_permissions?(version_id, default_permissions)
        repo_permissions = filter_repo_permissions(default_permissions)
        if repo_permissions.empty?
          log("Skipping integration version #{version_id}: no repository permissions") if verbose?
          return false
        end

        true
      end

      sig do
        params(
          installations: T::Array[IntegrationInstallationForTransition],
          integration_id: Integer
        ).returns(T::Boolean)
      end
      def process_installations_batch(installations, integration_id)
        installation_ids = installations.map(&:id)
        log_process_installation_batch(installation_ids, integration_id)

        # Load data about the whole batch so we avoid n+1 queries:
        permissions = load_installation_permissions(installation_ids)
        installation_ids_installed_on_all_repos = installation_ids_installed_on_all_repos_from(permissions)

        success = T.let(true, T::Boolean)
        installations.each do |installation|
          installation_success = backfill_installation_permissions(installation,
            installed_on_all_repos: installation_ids_installed_on_all_repos.include?(installation.id),
            permissions: permissions,
          )
          success = success && installation_success
        end

        success
      end

      # Private: Returns a Boolean indicating success.
      sig do
        params(
          installation: IntegrationInstallationForTransition,
          installed_on_all_repos: T::Boolean,
          permissions: T::Array[PermissionForTransition]
        ).returns(T::Boolean)
      end
      def backfill_installation_permissions(installation, installed_on_all_repos:, permissions:)
        if installed_on_all_repos
          if has_repo_metadata_permission?(installation, permissions, installed_on_all_repos: true)
            log_skipped_installation_permission_backfill(installation, permissions, installed_on_all_repos: true)
            return true
          end

          target_id = installation[:target_id]
          error = create_permission(installation.id, subject_type: ALL_USER_REPO_METADATA_SUBJECT_TYPE,
            subject_id: target_id)

          if verbose? || error
            verb = if error
              T.let("Failed to add", String)
            else
              T.let(dry_run? ? "Would add" : "Added", String)
            end
            suffix = error ? ": #{error}" : ""
            log("#{verb} metadata permission for installation #{installation.id} on all repositories for " \
              "user #{target_id}#{suffix}")
          end

          error.nil?
        else
          success = T.let(true, T::Boolean)
          total_repo_ids = 0

          each_repository_ids_batch_for(installation.id) do |repository_ids|
            batch_success = process_repository_ids_batch(repository_ids, installation, permissions)
            total_repo_ids += repository_ids.size
            success = success && batch_success
          end

          if verbose?
            units = "repository".pluralize(total_repo_ids)
            log("Processed #{total_repo_ids} #{units} for installation #{installation.id}")
          end

          success
        end
      end

      sig do
        params(
          installation: IntegrationInstallationForTransition,
          permissions: T::Array[PermissionForTransition],
          installed_on_all_repos: T::Boolean,
          repository_id: T.nilable(Integer)
        ).returns(T::Boolean)
      end
      def has_repo_metadata_permission?(installation, permissions, installed_on_all_repos: false, repository_id: nil)
        if installed_on_all_repos
          permissions.any? do |permission|
            permission[:actor_id] == installation.id &&
              permission[:subject_id] == installation[:target_id] &&
              permission[:subject_type] == ALL_USER_REPO_METADATA_SUBJECT_TYPE
          end
        else
          permissions.any? do |permission|
            permission[:actor_id] == installation.id &&
              permission[:subject_id] == repository_id &&
              permission[:subject_type] == REPO_SPECIFIC_METADATA_SUBJECT_TYPE
          end
        end
      end

      sig do
        params(
          repository_ids: T::Array[Integer],
          installation: IntegrationInstallationForTransition,
          permissions: T::Array[PermissionForTransition]
        ).returns(T::Boolean)
      end
      def process_repository_ids_batch(repository_ids, installation, permissions)
        log_repository_batch(repository_ids, installation.id)

        success = T.let(true, T::Boolean)
        repository_ids.each do |repo_id|
          if has_repo_metadata_permission?(installation, permissions, installed_on_all_repos: false, repository_id: repo_id)
            log_skipped_installation_permission_backfill(installation, permissions, repository_id: repo_id)
            next
          end

          error = create_permission(installation.id, subject_type: REPO_SPECIFIC_METADATA_SUBJECT_TYPE,
            subject_id: repo_id)

          if error || verbose?
            verb = if error
              "Failed to add"
            else
              dry_run? ? "Would have added" : "Added"
            end
            suffix = error ? ": #{error}" : ""
            log("#{verb} metadata permission for installation #{installation.id} on repository #{repo_id}#{suffix}")
          end

          success = success && error.nil?
        end

        success
      end

      # Private: Returns a Boolean indicating success.
      sig { params(version_id: Integer, integration_id: Integer).returns(T::Boolean) }
      def create_default_integration_permission(version_id:, integration_id:)
        error = T.let(nil, T.nilable(String))
        unless dry_run?
          write_to(model_class: DefaultIntegrationPermissionForTransition) do
            begin
              DefaultIntegrationPermissionForTransition.create!(
                integration_version_id: version_id,
                integration_id: integration_id,
                resource: "metadata",
                action: DEFAULT_INTEGRATION_PERMISSION_READ_ACTION,
              )
            rescue => err
              error = err.message
            end
          end
        end

        if verbose? || error
          verb = if error
            "Failed to add"
          else
            dry_run? ? "Would add" : "Added"
          end
          suffix = error ? ": #{error}" : ""
          log("#{verb} metadata permission to version #{version_id} for integration #{integration_id}#{suffix}")
        end

        error.nil?
      end

      # Private: Returns an error message on failure or nil on success.
      sig { params(installation_id: Integer, subject_type: String, subject_id: Integer).returns(T.nilable(String)) }
      def create_permission(installation_id, subject_type:, subject_id:)
        if dry_run?
          @total_perms_backfilled = T.must(@total_perms_backfilled) + 1
          return
        end

        error = T.let(nil, T.nilable(String))
        write_to(model_class: PermissionForTransition) do
          begin
            PermissionForTransition.create!(
              actor_type: "IntegrationInstallation",
              actor_id: installation_id,
              subject_type: subject_type,
              subject_id: subject_id,
              action: PERMISSION_READ_ACTION,
              priority: PERMISSION_DIRECT_PRIORITY,
            )
            @total_perms_backfilled = T.must(@total_perms_backfilled) + 1
          rescue => err
            error = err.message
            @total_perms_failed = T.must(@total_perms_failed) + 1
          end
        end

        error
      end

      sig do
        params(
          integration_id: Integer,
          version_id: Integer,
          block: T.proc.params(installations: T::Array[IntegrationInstallationForTransition]).void
        ).void
      end
      def each_installations_batch_for(integration_id, version_id:, &block)
        last_installation_id = if single_integration_version_targeted? && @installation_start_id
          # last_installation_id is exclusive and we want installation_start_id to be inclusive:
          @installation_start_id - 1
        end
        installations = installations_batch_for(integration_id, version_id: version_id,
          last_installation_id: last_installation_id)

        while installations.present?
          yield installations

          last_installation_id = installations.last&.id
          return if last_installation_id.nil? || installations.size < BATCH_SIZE

          installations = installations_batch_for(integration_id, version_id: version_id,
            last_installation_id: last_installation_id)
        end
      end

      sig do
        params(
          integration_id: Integer,
          version_id: Integer,
          last_installation_id: T.nilable(Integer)
        ).returns(T::Array[IntegrationInstallationForTransition])
      end
      def installations_batch_for(integration_id, version_id:, last_installation_id: nil)
        scope = IntegrationInstallationForTransition.where(integration_id: integration_id,
          integration_version_id: version_id).order(:id).limit(BATCH_SIZE).select(:id, :target_id, :integration_id)
        unless last_installation_id.nil?
          scope = scope.where("id > ?", last_installation_id)
        end
        if installation_end_id && single_integration_version_targeted?
          scope = scope.where("id <= ?", installation_end_id)
        end
        scope.to_a
      end

      sig { params(installation_ids: T::Array[Integer]).returns(T::Set[Integer]) }
      def load_installation_ids_using_repo_permissions(installation_ids)
        PermissionForTransition.where(
          actor_type: "IntegrationInstallation",
          actor_id: installation_ids,
          subject_type: non_metadata_repo_subject_types,
        ).select(:actor_id).distinct.pluck(:actor_id).to_set
      end

      sig do
        params(
          installation_id: Integer,
          block: T.proc.params(repo_ids: T::Array[Integer]).void
        ).void
      end
      def each_repository_ids_batch_for(installation_id, &block)
        repo_ids = repository_ids_batch_for(installation_id, last_repo_id: nil)

        while repo_ids.present?
          yield repo_ids

          last_repo_id = repo_ids.last
          return if last_repo_id.nil? || repo_ids.size < BATCH_SIZE

          repo_ids = repository_ids_batch_for(installation_id, last_repo_id: last_repo_id)
        end
      end

      sig { params(installation_id: Integer, last_repo_id: T.nilable(Integer)).returns(T::Array[Integer]) }
      def repository_ids_batch_for(installation_id, last_repo_id: nil)
        subject_types = repo_subject_types.map { |st| "Repository/#{st}" }
        scope = PermissionForTransition.where(
          actor_type: "IntegrationInstallation",
          actor_id: installation_id,
          subject_type: subject_types,
        ).order(:subject_id).limit(BATCH_SIZE)
        unless last_repo_id.nil?
          scope = scope.where("subject_id > ?", last_repo_id)
        end
        scope.distinct.pluck(:subject_id)
      end

      sig { params(version_ids: T::Array[Integer]).returns(T::Hash[Integer, T::Hash[String, Symbol]]) }
      def load_default_permissions(version_ids)
        default_permission_records_by_version = DefaultIntegrationPermissionForTransition
          .where(integration_version_id: version_ids)
          .group_by(&:integration_version_id)
        version_ids.each_with_object({}) do |version_id, result|
          default_permission_records = default_permission_records_by_version[version_id] || []
          result[version_id] = default_permission_records.each_with_object({}) do |record, memo|
            memo[record.resource] = DEFAULT_INTEGRATION_PERMISSION_ACTIONS[record.action]
          end
        end
      end

      sig { params(installation_ids: T::Array[Integer]).returns(T::Array[PermissionForTransition]) }
      def load_installation_permissions(installation_ids)
        last_permission_id = T.let(nil, T.nilable(Integer))
        permissions = permissions_batch_for(installation_ids, last_permission_id: last_permission_id)

        while permissions.present? && last_permission_id != permissions.last&.id
          last_permission_id = permissions.last&.id
          return permissions if last_permission_id.nil? || permissions.size < BATCH_SIZE

          permissions += permissions_batch_for(installation_ids, last_permission_id: last_permission_id)
        end

        permissions
      end

      sig do
        params(
          installation_ids: T::Array[Integer],
          last_permission_id: T.nilable(Integer)
        ).returns(T::Array[PermissionForTransition])
      end
      def permissions_batch_for(installation_ids, last_permission_id: nil)
        log_loading_permissions_batch(installation_ids, last_permission_id)
        scope = PermissionForTransition.where(
          actor_type: "IntegrationInstallation",
          actor_id: installation_ids,
          subject_type: repo_metadata_subject_types.union(all_repos_subject_types).to_a,
        ).order(:id).limit(BATCH_SIZE).select(:id, :subject_type, :subject_id, :actor_id)
        unless last_permission_id.nil?
          scope = scope.where("id > ?", last_permission_id)
        end
        scope.to_a
      end

      sig { params(permissions: T::Array[PermissionForTransition]).returns(T::Set[Integer]) }
      def installation_ids_installed_on_all_repos_from(permissions)
        all_repos_subject_types = self.all_repos_subject_types
        permissions.select { |permission| all_repos_subject_types.include?(permission[:subject_type]) }
          .map { |permission| permission[:actor_id] }.to_set
      end

      sig { params(permissions: T::Hash[String, Symbol]).returns(T::Hash[String, Symbol]) }
      def filter_repo_permissions(permissions)
        T.unsafe(permissions).slice(*repo_subject_types)
      end

      sig { returns T::Array[String] }
      memoize def repo_subject_types
        GitHub.enterprise? ? GHES_REPO_SUBJECT_TYPES : DOTCOM_REPO_SUBJECT_TYPES
      end

      sig { returns T::Array[String] }
      memoize def non_metadata_repo_subject_types
        (repo_subject_types.map { |st| "Repository/#{st}" } +
          repo_subject_types.map { |st| "User/repositories/#{st}" }) -
            [REPO_SPECIFIC_METADATA_SUBJECT_TYPE, ALL_USER_REPO_METADATA_SUBJECT_TYPE]
      end

      sig { returns T::Set[String] }
      memoize def all_repos_subject_types
        (GitHub.enterprise? ? GHES_REPO_TYPE_PREFIXED_SUBJECT_TYPES : DOTCOM_REPO_TYPE_PREFIXED_SUBJECT_TYPES).to_set
      end

      sig { returns T::Set[String] }
      memoize def repo_metadata_subject_types
        Set.new([REPO_SPECIFIC_METADATA_SUBJECT_TYPE, ALL_USER_REPO_METADATA_SUBJECT_TYPE])
      end

      sig { void }
      def log_about_given_arguments
        if installation_start_id
          if single_integration_version_targeted?
            log("Will start from integration installation #{installation_start_id}")
          else
            log("Warning: ignoring installation_start_id=#{installation_start_id} argument because more than one " \
              "integration version will be processed")
          end
        end

        if installation_end_id
          if single_integration_version_targeted?
            log("Will end with integration installation #{installation_end_id}")
          else
            log("Warning: ignoring installation_end_id=#{installation_end_id} argument because more than one " \
              "integration version will be processed")
          end
        end
      end

      sig { params(version_ids: T::Array[Integer]).void }
      def log_process_version_batch(version_ids)
        return unless verbose?

        total_in_batch = version_ids.size
        return if total_in_batch < 1

        units = "version".pluralize(total_in_batch)
        suffix = total_in_batch > 1 ? "s #{version_ids.first} to #{version_ids.last}" : " #{version_ids.first}"
        log("Processing batch of #{total_in_batch} integration #{units} with ID#{suffix}")
      end

      sig { params(version_ids: T::Array[Integer]).void }
      def log_backfilled_version_batch(version_ids)
        return if @total_default_perms_backfilled.nil? || @total_default_perms_backfilled < 1

        verb = dry_run? ? "Would have backfilled" : "Backfilled"
        version_ids_list = @backfilled_version_ids ? @backfilled_version_ids.to_a.sort.join(", ") : ""
        total_in_batch = version_ids.size
        batch_summary = total_in_batch > 1 ? "#{version_ids.first} to #{version_ids.last}" : "#{version_ids.first}"

        log("#{verb} repo metadata default integration permissions for #{@total_default_perms_backfilled} " \
          "integration versions in batch #{batch_summary}: #{version_ids_list}")
      end

      sig { params(version_ids: T::Array[Integer]).void }
      def log_batch_success_failure(version_ids)
        batch_summary = "(versions #{version_ids.first} to #{version_ids.last})"

        if @total_default_perms_failed && @total_default_perms_failed > 0
          units = "version".pluralize(@total_default_perms_failed)
          log("Failed to backfill repo metadata default integration permissions for #{@total_default_perms_failed} " \
            "integration #{units} in batch #{batch_summary}")
        elsif @total_default_perms_backfilled
          if @total_default_perms_backfilled > 0
            unless dry_run?
              log("All attempted default integration permission backfills in batch #{batch_summary} succeeded")
            end
          else
            log("No default integration permission backfills attempted in batch #{batch_summary}")
          end
        end

        if @total_perms_failed && @total_perms_failed > 0
          units = "record".pluralize(@total_perms_failed)
          log("Failed to create #{@total_perms_failed} permissions #{units} in batch #{batch_summary}")
        elsif @total_perms_backfilled
          if @total_perms_backfilled > 0
            units = "record".pluralize(@total_perms_backfilled)
            log("Created #{@total_perms_backfilled} permission #{units} for batch #{batch_summary}")
          else
            log("No permission records created for batch #{batch_summary}")
          end
        end
      end

      sig { params(installation_ids: T::Array[Integer], last_permission_id: T.nilable(Integer)).void }
      def log_loading_permissions_batch(installation_ids, last_permission_id)
        return unless verbose?

        total_installations = installation_ids.size
        return if total_installations < 1

        installation_id_summary = if total_installations > 1
          "s #{installation_ids.first} to #{installation_ids.last}"
        else
          " #{installation_ids.first}"
        end
        batch_descriptor = if last_permission_id.nil?
          "first batch of permissions"
        else
          "permissions after ID #{last_permission_id},"
        end
        log("Loading #{batch_descriptor} for installation ID#{installation_id_summary}")
      end

      sig { params(installation_ids: T::Array[Integer], integration_id: Integer).void }
      def log_process_installation_batch(installation_ids, integration_id)
        return unless verbose?

        total_in_batch = installation_ids.size
        return if total_in_batch < 1

        units = "installation".pluralize(total_in_batch)
        suffix = if total_in_batch > 1
          "s #{installation_ids.first} to #{installation_ids.last}"
        else
          " #{installation_ids.first}"
        end
        log("Processing batch of #{total_in_batch} #{units} for integration #{integration_id} with " \
          "installation ID#{suffix}")
      end

      sig do
        params(
          installation: IntegrationInstallationForTransition,
          permissions: T::Array[PermissionForTransition],
          installed_on_all_repos: T::Boolean,
          repository_id: T.nilable(Integer)
        ).void
      end
      def log_skipped_installation_permission_backfill(installation, permissions, installed_on_all_repos: false, repository_id: nil)
        installation_desc = installed_on_all_repos ? "all-repo" : "repo-specific"
        relevant_permission = permissions.detect do |permission|
          next false unless permission[:actor_id] == installation.id

          if installed_on_all_repos
            next false unless installation[:target_id] == permission[:subject_id]
          end

          if repository_id
            next false unless permission[:subject_id] == repository_id
          end

          if installed_on_all_repos
            permission[:subject_type] == ALL_USER_REPO_METADATA_SUBJECT_TYPE
          else
            permission[:subject_type] == REPO_SPECIFIC_METADATA_SUBJECT_TYPE
          end
        end

        if relevant_permission.nil?
          log("Warning: skipped backfill for #{installation_desc} installation #{installation.id} because thought " \
            "it had metadata permission, but could not pinpoint that permission record")
          return
        end

        if verbose?
          installation_suffix = if repository_id
            " for repository #{repository_id}"
          end
          log("Skipping backfill of #{installation_desc} installation #{installation.id}#{installation_suffix} " \
            "for integration #{installation[:integration_id]}: already has metadata permission <subject_type: " \
            "#{relevant_permission[:subject_type]}; subject_id: #{relevant_permission[:subject_id]}>")
        end
      end

      sig { params(repo_ids: T::Array[Integer], installation_id: Integer).void }
      def log_repository_batch(repo_ids, installation_id)
        return unless verbose?

        total_in_batch = repo_ids.size
        return if total_in_batch < 1

        units = "repository".pluralize(total_in_batch)
        suffix = total_in_batch > 1 ? "s #{repo_ids.first} to #{repo_ids.last}" : " #{repo_ids.first}"
        log("Processing batch of #{total_in_batch} #{units} for installation #{installation_id} " \
          "with repo ID#{suffix}")
      end
    end
  end
end

# Run as a single process if this script is run directly
if $0 == __FILE__
  # Supported command-line arguments:
  # write - run the transition in write mode to actually make changes
  # verbose - output more detailed log messages
  # start_id - specify an `integration_versions` ID to begin with (inclusive)
  # end_id - specify an `integration_versions` ID to stop at (inclusive)
  # installation_start_id - specify an `integration_installations` ID to begin with (inclusive); only
  #                         used when start_id and end_id specify a single version to process
  # installation_end_id - specify an `integration_installations` ID to stop at (inclusive); only
  #                       used when start_id and end_id specify a single version to process
  # read_batch_size - number of `integration_versions` rows to read at a time
  # process_batch_size - number of `integration_versions` rows to process at a time
  # workers - worker count for parallelization; set to 1 to disable parallelization
  args = GitHub::Transitions::Arguments.parse(ARGV,
    additional_arguments: %w(installation_end_id installation_start_id))
  GitHub::Transitions::BackfillVersionRepositoryMetadataPermission.new(args).run
end
