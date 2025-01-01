# typed: strict
# frozen_string_literal: true

require "monolith-twirp-registrymetadata-core"

module Api::Internal::Twirp::Registrymetadata
  module Core
    module V1
      # Handler for the MonolithTwirp::Registrymetadata::Core::V1::OwnerAPIService
      class OwnerAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: %w(packageregistry package_registry).freeze
        handles_service MonolithTwirp::Registrymetadata::Core::V1::OwnerAPIService

        # Public: Implementation of the GetOwnerInfo Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Registrymetadata::Core::V1::GetOwnerInfoRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Registrymetadata::Core::V1::GetOwnerInfoResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::Registrymetadata::Core::V1::GetOwnerInfoRequest,
            env: T::Hash[Symbol, T.untyped]
          ).returns(T.any(T::Hash[Symbol, T.untyped], Twirp::Error))
        end
        def get_owner_info(req, env)
          owner = User.find_by_login(req.name)
          return Twirp::Error.not_found("owner not found") if owner.nil?

          # This is to ensure calls (especially from registry metadata) resolve to the correct owner on proxima
          # Context: https://github.com/github/actions-sudo/issues/750
          if GitHub.multi_tenant_enterprise? && !GitHub::CurrentTenant.get.present?
            return Twirp::Error.failed_precondition("Tenant must be set in X-GitHub-Tenant header")
          end

          package_creation_visibility = :PACKAGE_VISIBILITY_PRIVATE
          inherit_access_from_repository = false

          if owner.organization?
            # https://github.com/github/c2c-package-registry/issues/3524
            if owner.members_can_publish_public_packages? &&
              GitHub.flipper[:packages_org_public_visibility].enabled?(owner) &&
              !GitHub.enterprise?
              package_creation_visibility = :PACKAGE_VISIBILITY_PUBLIC
            elsif owner.members_can_publish_internal_packages?
              # TODO: in the future we only want to allow orgs that belong to a Business/Enterprise account
              # to be able to publish internal packages
              package_creation_visibility = :PACKAGE_VISIBILITY_INTERNAL
            end

            # When removing this feature flag, move assignment outside if else.
            if GitHub.flipper[:packages_inherit_access_from_repository].enabled?(owner)
              inherit_access_from_repository = owner.packages_can_inherit_access_from_repo?
            end
          else
            inherit_access_from_repository = owner.packages_can_inherit_access_from_repo?
          end

          {
            owner_id: owner.id,
            package_creation_visibility: package_creation_visibility,
            inherit_access_from_repository: inherit_access_from_repository,
          }
        end

        sig do
          params(
            req: MonolithTwirp::Registrymetadata::Core::V1::GetInternalNamespacesForUserRequest,
            env: T::Hash[Symbol, T.untyped]
          ).returns(T.any(T::Hash[Symbol, T.untyped], Twirp::Error))
        end
        def get_internal_namespaces_for_user(req, env)
          return Twirp::Error.failed_precondition("must provide either a user name or id") if req.user_oneof.nil?

          user = req.user_id.zero? ? User.find_by_login(req.name) : User.find_by(id: req.user_id)

          return Twirp::Error.not_found("user not found") if user.nil?
          return Twirp::Error.failed_precondition("got organization but wanted user") if user.organization?

          internal_namespaces = user.organizations.pluck(:login)
          user_businesses = user.businesses

          user_businesses.each { |b| internal_namespaces = internal_namespaces | b.organizations.pluck(:login) }

          {
            internal_namespaces: internal_namespaces
          }
        end

        sig do
          params(
            req: MonolithTwirp::Registrymetadata::Core::V1::GetNamespacesForUserRequest,
            env: T::Hash[Symbol, T.untyped]
          ).returns(T.any(T::Hash[Symbol, T.untyped], Twirp::Error))
        end
        def get_namespaces_for_user(req, env)
          return Twirp::Error.failed_precondition("must provide either a user name or id") if req.user_oneof.nil?

          user = req.user_id.zero? ? User.find_by_login(req.name) : User.find_by(id: req.user_id)

          return Twirp::Error.not_found("user not found") if user.nil?
          return Twirp::Error.failed_precondition("got organization but wanted user") if user.organization?

          internal_namespaces = user.organizations.pluck(:login)
          internal_namespaces += Organization.joins(:business_membership).where(business_membership: { business_id: user.businesses.pluck(:id) }).pluck(:login)

          ids = T.let(user.owned_organization_ids, T::Array[Integer])
          admin_namespaces = Organization.find(ids).pluck(:login)

          {
            internal_namespaces: internal_namespaces.uniq,
            administered_namespaces: admin_namespaces
          }
        end
      end
    end
  end
end
