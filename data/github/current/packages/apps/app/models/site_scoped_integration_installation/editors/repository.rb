# typed: strict
# frozen_string_literal: true

# This class is responsible for granting access to either individual repositories or all repositories
# for existing SiteScopedIntegrationInstallations (SSII).
#
# The behavior is intended to be backward compatible with that of the SiteScopedIntegrationInstallation::Editor class.
#
# This behavior is primarily used by Codespaces, as they are currently the only integration
# that can mutate permissions after a token has been granted: https://github.com/github/ecosystem-apps/wiki/Tokens-lifecycle-and-dependencies#codespaces
class SiteScopedIntegrationInstallation
  module Editors
    class Repository < Base
      include GitHub::Memoizer

      extend T::Sig

      STATS_KEY_PREFIX = "site_scoped_integration_installation.editors.repository"

      PermissionsHash = T.type_alias { T::Hash[String, Symbol] }
      RepositoriesArray = T.type_alias { T::Array[::Repository] }

      sig do
        params(
          installation: SiteScopedIntegrationInstallation,
          repositories: RepositoriesArray,
          entry_point: Symbol,
          repository_permissions: PermissionsHash,
        ).returns(Result)
      end
      def self.grant(installation, repositories:, entry_point:, repository_permissions: {})
        new(installation, entry_point: entry_point).
          grant(repositories, repository_permissions: repository_permissions)
      end

      sig { returns(SiteScopedIntegrationInstallation) }
      attr_reader :installation

      sig { returns(RepositoriesArray) }
      attr_reader :repositories

      sig { returns(Symbol) }
      attr_reader :entry_point

      sig do
        params(
          installation: SiteScopedIntegrationInstallation,
          entry_point: Symbol
        ).void
      end
      def initialize(installation, entry_point:)
        @installation = installation
        @entry_point = entry_point
        @repositories = T.let([], RepositoriesArray)
        @requested_repository_permissions = T.let({}, PermissionsHash)
        @fallback_repository_permissions = T.let(::Repository::Resources.filter(installation.permissions), PermissionsHash)

        @authorization_details = T.let(nil, T.nilable(::ScopedInstallations::AuthorizationDetails::Structs::V1))

        if @installation.authorization_details.present?
          @authorization_details = @installation.authorization_details_struct
        end
      end

      sig do
        params(
          repositories: RepositoriesArray,
          repository_permissions: PermissionsHash,
        ).returns(Result)
      end
      def grant(repositories, repository_permissions: {})
        @repositories = repositories
        @requested_repository_permissions = build_repository_permissions(repository_permissions)

        with_instrumentation do
          if repository_access_escalated?
            Result.failed(:invalid_permissions)
          elsif !repositories_in_same_target? && !integration_installation_multiple_target_permissions?
            Result.failed(:multiple_target_permissions)
          elsif repositories_in_same_target? && installation.installed_on_all_repositories?
            # If different permissions are requested, we return success without
            # actually applying the permissions on all.
            # This is backwards compatible with the legacy Editor class but highlights
            # some of the issues with the current mutation-based approach.
            Result.success(installation)
          else
            install_on_repositories
          end
        end
      end

      private

      sig { params(repository_permissions: PermissionsHash).returns(PermissionsHash) }
      def build_repository_permissions(repository_permissions)
        filtered_permissions = T.let(::Repository::Resources.filter(repository_permissions), PermissionsHash)
        filtered_permissions.empty? ? @fallback_repository_permissions : filtered_permissions
      end

      sig { returns(T::Boolean) }
      def repository_access_escalated?
        result = PermissionsDiffer.new(
          previous_permissions: @fallback_repository_permissions,
          new_permissions: @requested_repository_permissions,
        )

        result.added_permissions.any? || (!can_upgrade_default_permissions? && result.upgraded_permissions.any?)
      end

      sig { returns(T::Boolean) }
      def can_upgrade_default_permissions?
        Apps::Internal.capable?(:upgrade_default_permissions, app: installation.integration)
      end

      sig { returns(T::Boolean) }
      memoize def repositories_in_same_target?
        repositories.flat_map(&:owner_id).include?(installation.target_id)
      end

      sig { returns(T::Boolean) }
      def integration_installation_multiple_target_permissions?
        Apps::Internal.capable?(:integration_installation_multiple_target_permissions, app: installation.integration)
      end

      sig { returns(Result) }
      def install_on_repositories
        resource_type = ::ScopedInstallations::AuthorizationDetails::ResourceType::Repository

        rows =
          @requested_repository_permissions.flat_map do |resource, action|
            if @authorization_details.present?
              @authorization_details.set_asymmetric_for(
                resource_type, resource, action, repositories.map(&:ability_id)
              )
            end

            repositories.flat_map do |repository|
              subject = repository.resources.public_send(resource) # rubocop:disable GitHub/AvoidObjectSendWithDynamicMethod
              expiration = installation.expires_at.to_i if installation.expires_at.present?

              ::Permissions::Service.installation_attributes_hash(
                actor: installation,
                subject: subject,
                action: action,
                expires_at: expiration
              )
            end
          end

        if @authorization_details.present?
          @installation.update!(authorization_details: @authorization_details.serialize)
        end

        ::Permissions::Service.grant_permissions!(rows, entry_point: entry_point)

        Result.success(installation)
      end

      sig { params(block: T.proc.returns(Result)).returns(Result) }
      def with_instrumentation(&block)
        result = block.call
        GitHub.dogstats.increment("#{STATS_KEY_PREFIX}.update", tags: ["result:#{result.status}"])
        result
      end
    end
  end
end
