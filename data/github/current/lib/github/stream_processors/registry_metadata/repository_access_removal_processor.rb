# typed: false
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module RegistryMetadata
      class RepositoryAccessRemovalProcessor < SingleMessageProcessor

        DEFAULT_GROUP_ID = "rms_repository_access_removal_processor"
        DEFAULT_SUBSCRIBE_TO = [
          /github.v1.RepositoryTransfer\Z/,
          /github.v1.RepositoryDeleted\Z/
        ].freeze

        TRANSFER_EVENT = "hydro.schemas.github.v1.RepositoryTransfer"
        DELETE_EVENT = "hydro.schemas.github.v1.RepositoryDeleted"

        options[:min_bytes] = 1
        options[:max_wait_time] = 0.2.seconds
        options[:max_bytes_per_partition] = 1.megabyte
        options[:start_from_beginning] = false

        # Initialize the RepositoryAccessRemovalProcessor
        def setup(**kwargs)
          options[:group_id] ||= DEFAULT_GROUP_ID
          options[:subscribe_to] ||= DEFAULT_SUBSCRIBE_TO
        end

        # Remove actions and codespaces access for a repository
        #
        # message - The repository transfer or delete hydro message
        #
        # Returns nothing
        def process_message(message)
          case message.schema
          when TRANSFER_EVENT
            handle_repository_transfer(message)
          when DELETE_EVENT
            handle_repository_deletion(message)
          end
        end

        private

        def handle_repository_transfer(message)
          previous_owner = message.value.dig(:previous_owner)

          if previous_owner.nil?
            return message.skip("previous_owner must be present")
          end

          previous_owner_obj = User.find_by(id: previous_owner[:id])

          if !FeatureFlag.vexi.enabled?(:rms_unlink_packages_on_repository_transfer, previous_owner_obj, default: true)
            return message.skip("rms_unlink_packages_on_repository_transfer ff not enabled")
          end

          transfer_state = message.value.dig(:state)
          transfer_criteria = message.value.dig(:criteria)
          if !(transfer_state == :RESPONDED || transfer_criteria == :IMMEDIATE)
            return message.skip("transfer_state must be responded and transfer_criteria must be immediate")
          end

          repo_id = message.value.dig(:repository, :id)
          repo = if FeatureFlag.vexi.enabled?(:repos_by_id_lib, default: false)
            Repositories.domain.by_id(repo_id)
          else
            Repository.find_by(id: repo_id)
          end
          return message.skip("repo not found") if repo.nil?

          remove_actions_access(repo_id, message)
          remove_codespaces_access(repo_id, previous_owner_obj.id, message)
        end

        def handle_repository_deletion(message)
          actor = message.value.dig(:actor)
          if actor.nil?
            return message.skip("actor must be present")
          end

          actor_obj = with_read do
            User.find_by(id: actor[:id])
          end

          repo_id = message.value.dig(:deleted_repository, :id)
          repo = if FeatureFlag.vexi.enabled?(:repos_by_id_lib, default: false)
            Repositories.domain.by_id(repo_id)
          else
            Repository.find_by(id: repo_id)
          end
          return message.skip("repo not found") if repo.nil?

          repo_owner = User.find_by(id: repo.owner_id)

          if !FeatureFlag.vexi.enabled?(:rms_unlink_packages_on_repository_transfer, repo_owner, default: true)
            return message.skip("rms_unlink_packages_on_repository_transfer ff not enabled")
          end

          remove_actions_access(repo_id, message)
          remove_codespaces_access(repo_id, actor_obj.id, message)
        end

        def remove_actions_access(repo_id, message)
          if repo_id <= 0
            return message.skip("repo_id must be present.")
          end

          actions_integration = Apps::Privileged.integration(:actions)
          unless actions_integration
            return message.skip("could not access actions integration")
          end

          ActiveRecord::Base.connected_to(role: :writing) do
            IntegrationAllowedPackage.throttle_with_retry(max_retry_count: 5) do
              # Revoke all old roles
              IntegrationAllowedPackage.where(repository_id: repo_id, integration_id: actions_integration.id).delete_all
            end

          rescue ActiveRecord::RecordInvalid
            return message.skip("could not write actions permission for repository")
          end
        end

        def remove_codespaces_access(repo_id, actor_id, message)
          if repo_id <= 0
            return message.skip("repo_id must be present.")
          end

          codespaces_integration = Apps::Privileged.integration(:codespaces_production)
          unless codespaces_integration
            return message.skip("could not access codespaces integration")
          end

          ActiveRecord::Base.connected_to(role: :writing) do
            IntegrationAllowedPackage.throttle_with_retry(max_retry_count: 5) do
              # Revoke all old roles
              old_data = IntegrationAllowedPackage.where(repository_id: repo_id, integration_id: codespaces_integration.id)

              if old_data.size > 0
                pkg_ids = old_data.pluck(:package_id)
                pkg_ids.each do |pkg_id|
                  Packages::RemovePackageCodespacesPermissionsForRepositoryJob.perform_later(repository_id: repo_id, package_id: pkg_id, user_id: actor_id,
                    entry_point: :stream_processor_registry_metadata_repository_access_removal
                  )
                end
                old_data.delete_all
              end
            end

          rescue ActiveRecord::RecordInvalid
            return message.skip("could not write codespaces permission for repository")
          end
        end

      end
    end
  end
end
