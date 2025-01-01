# typed: strict
# frozen_string_literal: true

class SiteScopedIntegrationInstallation
  module Creators
    class PrebuildCodespace < ScopedIntegrationInstallation::Creators::Base

      include ScopedIntegrationInstallation::PermissionRowsGenerator
      include CodespaceAuthorizationDetailsWriter

      STATS_KEY = "site_scoped_integration_installation.creators.prebuilt_codespace"
      TOKEN_AND_PERMISSIONS_EXPIRATION = T.let(25.hours, ActiveSupport::Duration)

      sig do
        params(
          integration: Integration,
          repository: Repository,
          code_path: String,
          branch: T.nilable(String),
          entry_point: T.any(NilClass, Symbol, ::Permissions::Service::EntryPoint),
        ).returns(::ScopedIntegrationInstallation::Result)
      end
      def self.perform(integration:, repository:, code_path:, branch: nil, entry_point: nil)
        new(integration:, repository:, code_path:, branch:, entry_point:).perform
      end

      sig { returns(Integration) }
      attr_reader :integration

      sig { returns(Repository) }
      attr_reader :repository

      sig { returns(T.nilable(String)) }
      attr_reader :branch

      sig { returns(T.any(NilClass, Symbol, ::Permissions::Service::EntryPoint)) }
      attr_reader :entry_point

      sig { returns(SiteScopedIntegrationInstallation) }
      attr_reader :installation

      sig { returns(InstallationTarget) }
      attr_reader :target

      sig do
        params(
          integration: Integration,
          repository: Repository,
          code_path: String,
          branch: T.nilable(String),
          entry_point: T.any(NilClass, Symbol, ::Permissions::Service::EntryPoint),
        ).void
      end
      def initialize(integration:, repository:, code_path:, branch:, entry_point: nil)
        @integration = integration
        @repository = repository
        @code_path = code_path
        @branch = branch
        @entry_point = entry_point

        @target = T.let(T.must(repository.owner), User)
        @installation = T.let(build_installation, SiteScopedIntegrationInstallation)
        @default_permissions = T.let(@integration.default_permissions, PermissionsHash)
      end

      sig { returns(::ScopedIntegrationInstallation::Result) }
      def perform
        validate_permissions!

        permission_rows = synthesize_permission_rows!
        @installation.authorization_details = synthesize_authorization_details!({ @target => permission_rows })

        ActiveRecord::Base.connected_to(role: :writing) { @installation.save! }

        case response = @installation.generate_token(code_path: @code_path)
        when GH::Result::Ok
          result = ::ScopedIntegrationInstallation::Result.success(@installation)
          result.credential = response.value.token_value
          result
        else
          log_permissions_error_details(StandardError.new(response.message))
          ::ScopedIntegrationInstallation::Result.failed("There was a problem while creating the token")
        end
      rescue ActiveRecord::ActiveRecordError,
        ScopedIntegrationInstallation::Result::Error,
        KeyError,
        JSON::Schema::ValidationError => e
        if @installation.persisted?
          ActiveRecord::Base.connected_to(role: :writing) do
            @installation.destroy!
          end
        end

        log_permissions_error_details(e)

        ::ScopedIntegrationInstallation::Result.failed(error_message_for_exception(e))
      end

      private

      sig { returns(SiteScopedIntegrationInstallation) }
      def build_installation
        SiteScopedIntegrationInstallation.new(
          integration: @integration,
          target: @target,
          expires_at: TOKEN_AND_PERMISSIONS_EXPIRATION.from_now
        )
      end

      sig { returns(PermissionsHash) }
      memoize def repository_permissions
        Repository::Resources.filter(@default_permissions)
      end

      sig { params(permissions: PermissionsHash).returns(PermissionsHash) }
      def with_action_set_to_read(permissions)
        permissions
          .reject { |resource, _action| ::Permissions::ResourceRegistry.writeonly_subject_type?(resource) }
          .transform_values { :read }
      end

      sig { returns(T::Array[PermissionRow]) }
      def synthesize_permission_rows!
        rows = []

        # Attempt to grant package permissions first so that we don't try to
        # synthesize the rest in vain.
        rows.concat(
          generate_and_validate_permission_rows_for_packages!(
            integration: @integration,
            installation: @installation,
            target: @target,
            repositories: [repository],
            permissions: @default_permissions,
          )
        )

        # Repository permissions on the Codespace's repository
        rows.concat(
          permission_rows_for_subjects(
            actor: @installation,
            subjects: [repository],
            permissions: with_action_set_to_read(repository_permissions)
          )
        )

        # Repository permissions for DevContainer configurations
        rows.concat(permission_rows_for_prebuilt_configurations) if branch.present?

        # Actor and action on each row is the same, so we deduplicate by subject
        rows.uniq { |row| row.values_at(:subject_id, :subject_type) }
      end

      sig { returns(T::Hash[Repository, PermissionsHash]) }
      def consented_permissions_from_prebuild_configurations_per_repository
        ref = repository.refs.find(branch)
        return {} unless ref

        configurations = Codespaces::PrebuildConfiguration.where(repository:, branch:)
        return {} if configurations.empty?

        configurations.reduce({}) do |consented_permissions, configuration|
          oid = repository.refs.find(branch)&.target_oid
          dc = Codespaces::DevContainer.new(
            repository: repository,
            oid: oid, filepath:
            configuration.devcontainer_path,
            is_prebuild: true
          )

          repo_permissions = dc.diff_repository_permissions(
            prebuild_configuration_id: configuration.id
          )

          log_details_of_configuration(repository, configuration, T.must(branch), repo_permissions)
          consented_permissions.deep_merge(repo_permissions.consented)
        end
      end

      sig { returns(T::Array[PermissionRow]) }
      def permission_rows_for_prebuilt_configurations
        consented_permissions_from_prebuild_configurations_per_repository
          .reduce([]) do |rows, (repo, permissions)|
            rows.concat(
              permission_rows_for_subjects(
                actor: @installation,
                subjects: [repo],
                permissions: with_action_set_to_read(permissions)
              )
            )
          end
      end

      sig { void }
      def validate_app_capability!
        unless Apps::Privileged.capable?(:installed_globally, app: @integration)
          raise_error "Integration can't be globally installed"
        end

        if @integration.feature_flag_enabled?(:disabled_global_apps, default: false)
          raise_error "Global-Apps is disabled for this integration"
        end
      end

      sig { void }
      def validate_target_accessibility!
        unless Apps::Privileged.target_accessible_to_limited_app?(repository.owner, app: @integration)
          raise_error "This integration doesn't have access to the given target"
        end
      end

      sig { void }
      def validate_permissions!
        validate_app_capability!
        validate_target_accessibility!
      end

      sig do
        params(
          repository: Repository,
          configuration: Codespaces::PrebuildConfiguration,
          ref: String,
          repo_permissions: Codespaces::DevContainerConfig::Codespaces::PermissionsDiff
        ).void
      end
      def log_details_of_configuration(repository, configuration, ref, repo_permissions)
        GitHub.logger.info(
          "code.namespace" => "Codespaces::Tokens",
          "code.function" => "repo_permissions_for_prebuild_configuration",
          "gh.repo.id" => repository.id,
          "gh.codespaces.prebuild_configuration.id" => configuration.id,
          "git.ref" => ref,
          "gh.codespaces.prebuild_token_mint_branch_present" => true,
          "gh.codespaces.prebuild_token_mint_devcontainer_present" => true,
          "gh.codespaces.prebuild_token_mint_consented_permissions" => repo_permissions.consented,
          "gh.codespaces.prebuild_token_mint_requested_permissions" => repo_permissions.requested
        )
      end
    end
  end
end
