# typed: strict
# frozen_string_literal: true

class SiteScopedIntegrationInstallation
  module Editors

    # Packages Permissions Availability
    #
    # TODO: Keep this until we know what to do with Codespaces.
    # See https://github.com/github/package-registry-team/issues/7344
    class Packages < Base
      sig do
        params(
          installation: SiteScopedIntegrationInstallation,
          package: PackageRegistry::PackageSubject,
          entry_point: T.nilable(Symbol)
        ).returns(Result)
      end
      def self.grant(installation, package, entry_point: nil)
        new(installation, entry_point).perform(:grant, package)
      end

      sig do
        params(
          installation: SiteScopedIntegrationInstallation,
          package: PackageRegistry::PackageSubject,
          entry_point: T.nilable(Symbol)
        ).returns(Result)
      end
      def self.revoke(installation, package, entry_point: nil)
        new(installation, entry_point).perform(:revoke, package)
      end

      sig { params(installation: SiteScopedIntegrationInstallation, entry_point: T.nilable(Symbol)).void }
      def initialize(installation, entry_point)
        @installation = installation
        @entry_point = entry_point
      end

      sig { params(action: Symbol, package: PackageRegistry::PackageSubject).returns(Result) }
      def perform(action, package)
        validation_result = validate_capabilities(@installation)
        return validation_result unless validation_result.success?

        unless Apps::Internal.capable?(:manage_packages_permissions, app: @installation.integration)
          return ::SiteScopedIntegrationInstallation::Editors::Result.failed(:invalid_permissions)
        end

        begin
          case action
          when :grant
            grant_access_on(package)
          when :revoke
            revoke_access_on(package)
          else
            return ::SiteScopedIntegrationInstallation::Editors::Result.failed(:invalid_action)
          end

          GitHub.dogstats.increment("site_scoped_integration_installation.editors.packages", tags: ["result:success", "action:#{action}"])
          ::SiteScopedIntegrationInstallation::Editors::Result.success(@installation)
        rescue RuntimeError => boom
          GitHub.dogstats.increment("site_scoped_integration_installation.editors.packages", tags: ["result:failure", "action:#{action}"])
          ::SiteScopedIntegrationInstallation::Editors::Result.error(boom)
        end
      end

      private

      sig { params(package: PackageRegistry::PackageSubject).void }
      def grant_access_on(package)
        subject = package_subject(package)
        action  = package_action(package)

        options = {
          actor: @installation,
          subject: subject,
          action: action,
        }

        if @installation.expires_at.present?
          options[:expires_at] = @installation.expires_at.to_i
        end

        row = ::Permissions::Service.app_attributes(**options)
        ::Permissions::Service.grant_permissions([row], entry_point: @entry_point)
      end

      sig { params(package: PackageRegistry::PackageSubject).void }
      def revoke_access_on(package)
        subject = package_subject(package)
        action  = package_action(package)

        ::Permissions::Service.revoke_permissions(
          actor_id: @installation.ability_id,
          actor_type: @installation.ability_type,
          subject_id: subject.ability_id,
          subject_type: subject.ability_type,
          action: Permission.actions[action],
          priority: Permission.priorities[:direct],
          entry_point: @entry_point
        )
      end

      sig { params(package: PackageRegistry::PackageSubject).returns(Symbol) }
      def package_action(package)
        package.access_type == "administration" ? :write : :read
      end

      sig { params(package: PackageRegistry::PackageSubject).returns(IntegrationInstallation::AbilityCollection) }
      def package_subject(package)
        package.resources.public_send(package.access_type) # rubocop:disable GitHub/AvoidObjectSendWithDynamicMethod
      end
    end
  end
end
