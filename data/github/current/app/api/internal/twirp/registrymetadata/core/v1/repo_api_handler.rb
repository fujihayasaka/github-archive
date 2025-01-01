# typed: true
# frozen_string_literal: true

require "monolith-twirp-registrymetadata-core"

module Api::Internal::Twirp::Registrymetadata
  module Core
    module V1
      # Handler for the MonolithTwirp::Registrymetadata::Core::V1::RepoAPIService
      class RepoAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: %w(packageregistry package_registry).freeze
        handles_service MonolithTwirp::Registrymetadata::Core::V1::RepoAPIService

        # Public: Implementation of the GetRepoId Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Registrymetadata::Core::V1::GetRepoIdRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Registrymetadata::Core::V1::GetRepoIdResponse, or a Twirp::Error.
        def get_repo_id(req, env)
          repo = Repository.with_name_with_owner(req.repo_name_with_owner)
          return Twirp::Error.not_found("repo not found") if repo.nil?
          GitHub.cache.delete("repository:packages:count:#{repo.id}")
          {
            repo_id: repo.id,
          }
        end

        # Public: Implementation of the GetRepoPermissions Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Registrymetadata::Core::V1::GetRepoPermissionsRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Registrymetadata::Core::V1::GetRepoPermissionsResponse, or a Twirp::Error.
        def get_repo_permissions(req, env)
          repo_id = req.repo_id
          user_id = req.user_id

          if repo_id <= 0
            return Twirp::Error.invalid_argument("must be non-empty", argument: "repo_id")
          end

          if user_id <= 0
            return Twirp::Error.invalid_argument("must be non-empty", argument: "user_id")
          end

          user = User.find_by(id: user_id)
          if user.nil?
            return Twirp::Error.not_found("user does not exist", argument: "user_id")
          end

          repo = Repository.find_by(id: repo_id)
          if repo.nil?
            return Twirp::Error.not_found("repo does not exist", argument: "repo_id")
          end

          access_level = case repo.access_level_for(user)
          when nil
            :USER_PERMISSION_NO_ACCESS
          when :read
            :USER_PERMISSION_READ
          when :write
            :USER_PERMISSION_WRITE
          when :admin
            :USER_PERMISSION_ADMIN
          else
            :USER_PERMISSION_INVALID
          end

          { "permission": access_level }
        end

        # Public: Implementation of the SyncAccess Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Registrymetadata::Core::V1::SyncAccessRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Registrymetadata::Core::V1::SyncAccessResponse, or a Twirp::Error.
        def sync_access(req, env)
          if req.repo_id <= 0
            return Twirp::Error.invalid_argument("must be valid", argument: "repo_id")
          end

          if req.package_id <= 0
            return Twirp::Error.invalid_argument("must be valid", argument: "package_id")
          end

          repo = Repository.find_by(id: req.repo_id)
          return Twirp::Error.not_found("repo not found") if repo.nil?

          package = PackageRegistry::Package.new(PackageWrapper.new(req.package_id)).tap do |p|
            p.owner_id = repo.owner_id
          end

          actions_integration = Apps::Privileged.integration(:actions)
          unless actions_integration
            return Twirp::Error.internal("could not access actions integration")
          end

          ActiveRecord::Base.connected_to(role: :writing) do
            IntegrationAllowedPackage.transaction do
              # Grant repository maintainer access
              IntegrationAllowedPackage.new(repository_id: req.repo_id, access_type: :maintainer, package_id: req.package_id, integration_id: actions_integration.id).save!

              # Sync user and team permissions from repo
              package.sync_access_from_repo(repository: repo)
            end
          rescue ActiveRecord::RecordInvalid
            return Twirp::Error.internal("could not write actions permission for repository")
          end

          {}
        end

        # Public: Implementation of the GetRepoInfo Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Registrymetadata::Core::V1::GetRepoInfoRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Registrymetadata::Core::V1::GetRepoInfoResponse, or a Twirp::Error.
        def get_repo_info(req, env)
          repo = Repository.with_name_with_owner(req.repo_name_with_owner)
          return Twirp::Error.not_found("repo not found") if repo.nil?
          visibility = :VISIBILITY_PRIVATE
          if repo.public?
            visibility = :VISIBILITY_PUBLIC
          elsif repo.internal?
            visibility = :VISIBILITY_INTERNAL
          end

          policy = repo.is_actions_repository_sharing_applicable? ? repo.actions_repository_share_policy : Configurable::ActionsRepositorySharePolicy::NONE
          sharing_policy = case policy
          when Configurable::ActionsRepositorySharePolicy::NONE
            MonolithTwirp::Registrymetadata::Core::V1::ActionRepoSharingPolicy::ACTION_REPO_SHARING_POLICY_NONE
          when Configurable::ActionsRepositorySharePolicy::ACCESSIBLE_SAME_ORGANIZATION
            MonolithTwirp::Registrymetadata::Core::V1::ActionRepoSharingPolicy::ACTION_REPO_SHARING_POLICY_ACCESSIBLE_SAME_ORG
          when Configurable::ActionsRepositorySharePolicy::ACCESSIBLE_SAME_BUSINESS
            MonolithTwirp::Registrymetadata::Core::V1::ActionRepoSharingPolicy::ACTION_REPO_SHARING_POLICY_ACCESSIBLE_SAME_BUSINESS
          when Configurable::ActionsRepositorySharePolicy::ACCESSIBLE_SAME_USER
            MonolithTwirp::Registrymetadata::Core::V1::ActionRepoSharingPolicy::ACTION_REPO_SHARING_POLICY_ACCESSIBLE_SAME_USER
          end
          {
            owner_id: repo.owner_id,
            repo_id: repo.id,
            visibility: visibility,
            sharing_policy: sharing_policy,
          }
        end

        # Public: Implementation of the RemoveActionsAccess Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Registrymetadata::Core::V1::RemoveActionsAccessRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Registrymetadata::Core::V1::RemoveActionsAccessResponse, or a Twirp::Error.
        def remove_actions_access(req, env)
          if req.repo_id <= 0
            return Twirp::Error.invalid_argument("must be valid", argument: "repo_id")
          end

          if req.package_id <= 0
            return Twirp::Error.invalid_argument("must be valid", argument: "package_id")
          end

          repo = Repository.find_by(id: req.repo_id)
          return Twirp::Error.not_found("repo not found") if repo.nil?

          actions_integration = Apps::Privileged.integration(:actions)
          unless actions_integration
            return Twirp::Error.internal("could not access actions integration")
          end

          ActiveRecord::Base.connected_to(role: :writing) do

            # Revoke all old roles
            IntegrationAllowedPackage.where(repository_id: req.repo_id, package_id: req.package_id, integration_id: actions_integration.id).delete_all

          rescue ActiveRecord::RecordInvalid
            return Twirp::Error.internal("could not write actions permission for repository")
          end

          {}
        end

        # Public: Implementation of the RemoveCodespacesAccess Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Registrymetadata::Core::V1::RemoveCodespacesAccessRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Registrymetadata::Core::V1::RemoveCodespacesAccessResponse, or a Twirp::Error.
        def remove_codespaces_access(req, env)
          if req.repo_id <= 0
            return Twirp::Error.invalid_argument("must be valid", argument: "repo_id")
          end

          if req.package_id <= 0
            return Twirp::Error.invalid_argument("must be valid", argument: "package_id")
          end

          repo = Repository.find_by(id: req.repo_id)
          return Twirp::Error.not_found("repo not found") if repo.nil?

          codespaces_integration = Apps::Privileged.integration(:codespaces_production)
          unless codespaces_integration
            return Twirp::Error.internal("could not access codespaces integration")
          end

          ActiveRecord::Base.connected_to(role: :writing) do

            # Revoke all old roles
            IntegrationAllowedPackage.where(repository_id: req.repo_id, package_id: req.package_id, integration_id: codespaces_integration.id).delete_all
            Packages::RemovePackageCodespacesPermissionsForRepositoryJob.perform_later(
              repository_id: req.repo_id,
              package_id: req.package_id,
              user_id: req.actor_id,
              entry_point: :twirp_api_registry_metadata_repo_api_handler_remove_permissions_for_repository_job_remove_access,
            )

          rescue ActiveRecord::RecordInvalid
            return Twirp::Error.internal("could not write codespaces permission for repository")
          end

          {}
        end

        # Public: Implementation of the RemoveBulkIntegrationAccess Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Registrymetadata::Core::V1::RemoveBulkIntegrationAccessRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Registrymetadata::Core::V1::RemoveBulkIntegrationAccessResponse, or a Twirp::Error.
        def remove_bulk_integration_access(req, env)
          if req.package_id <= 0
            return Twirp::Error.invalid_argument("must be valid", argument: "package_id")
          end

          actions_integration = Apps::Privileged.integration(:actions)
          unless actions_integration
            return Twirp::Error.internal("could not access actions integration")
          end

          ActiveRecord::Base.connected_to(role: :writing) do
            IntegrationAllowedPackage.throttle_with_retry(max_retry_count: 5) do
              # Revoke all old roles
              IntegrationAllowedPackage.where(package_id: req.package_id, integration_id: actions_integration.id).delete_all
            end
          rescue ActiveRecord::RecordInvalid
            return Twirp::Error.internal("could not write actions permission for repository")
          end

          codespaces_integration = Apps::Privileged.integration(:codespaces_production)
          unless codespaces_integration
            return Twirp::Error.internal("could not access codespaces integration")
          end

          ActiveRecord::Base.connected_to(role: :writing) do
            IntegrationAllowedPackage.throttle_with_retry(max_retry_count: 5) do
              # Revoke all old roles
              iap_codespaces = IntegrationAllowedPackage.where(package_id: req.package_id, integration_id: codespaces_integration.id)
              user_id = User.ghost&.id # hardcoded user_id for login - ghost as we do not store deleted_by in packages also user_id not used anywhere in permissions
              if iap_codespaces.size > 0
                repo_ids = iap_codespaces.pluck(:repository_id)
                repo_ids.each do |repo_id|
                  Packages::RemovePackageCodespacesPermissionsForRepositoryJob.perform_later(
                    repository_id: repo_id,
                    package_id: req.package_id,
                    user_id: user_id,
                    entry_point: :twirp_api_registry_metadata_repo_api_handler_remove_permissions_for_repository_job_remove_bulk,
                  )
                end
                iap_codespaces.delete_all
              end
            end
          rescue ActiveRecord::RecordInvalid
            return Twirp::Error.internal("could not write codespaces permission for repository")
          end

          {}
        end
      end
    end
  end
end
