# typed: false
# frozen_string_literal: true

require "monolith-twirp-registrymetadata-core"

module Api::Internal::Twirp::Registrymetadata
  module Core
    module V1
      # Handler for the MonolithTwirp::Registrymetadata::Core::V1::LoginAPIService
      class CollabAuthAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: %w(packageregistry package_registry).freeze
        handles_service MonolithTwirp::Registrymetadata::Core::V1::AuthAPIService
        connected_to_writing_for :add_collaborator_access_for_package # this param make sure to get write permission for our role

        #Public: Implementation of the AddCollaboratorAccessForPackage Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Registrymetadata::Core::V1::AddCollaboratorAccessForPackageRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Registrymetadata::Core::V1::AddCollaboratorAccessForPackageResponse, or a Twirp::Error.
        def add_collaborator_access_for_package(req, env)

          package = PackageRegistry::CollabPackage.new(req.package)
          actor_id = req.actor_id # this is actor id
          role_to_grant = req.role # this is role to be granted
          owner_id = req.package.owner_id # this is organization id

          actor = User.find_by(id: actor_id)
          if actor.nil?
            return Twirp::Error.not_found("Actor not found")
          end
          owner = User.find_by(id: owner_id)
          if owner.nil?
            return Twirp::Error.not_found("Owner not found")
          end

          if owner.is_a?(Organization)
            org = Organization.find_by(id: owner_id)
            if !org.member?(actor)
              return Twirp::Error.not_found("User is not a part of the organization")
            end
          end

          unless Role::PACKAGES_SYSTEM_ROLES.include?(role_to_grant)
            return Twirp::Error.invalid_argument("Invalid role to grant")
          end

          new_role = Role.internal_role_by_name(role_to_grant)

          package_roles = Role.system_package_roles.to_a
          package_roles.delete(new_role)
          current_roles = UserRole.where(role_id: package_roles.map(&:id)).where(target_type: "Package", target_id: package.id, actor_id: actor.id)
          if current_roles.nil?
            return Twirp::Error.failed_precondition("Did not expect current_roles to be nil")
          end
          if !current_roles.empty?
            return Twirp::Error.failed_precondition("Actor already has a different role assigned")
          end

          begin
            # Grant the new role
            result = Permissions::Granters::RoleGranter.new(
              actor: actor, target: package, role: new_role
            ).grant_unless_exists!

            if result.success?
              { result: "success" }
            else
              { result: "failed" }
            end
          rescue ::Permissions::Granters::RoleGranter::GrantFailure => e
            { result: "failed" + e.message }
          end
        end
      end
    end
  end
end
