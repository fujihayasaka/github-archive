# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module UserMetadata
      module Events
        class RepositoryEvent < UserMetadataEvent
          SKIP_REASON = "No repository owner(s) found"

          TRANSFER_EVENT = "hydro.schemas.github.v1.RepositoryTransfer"
          DELETE_EVENT = "hydro.schemas.github.v1.RepositoryDeleted"

          def skip?
            users.empty?
          end

          def skip_reason
            SKIP_REASON
          end

          def users
            case processor.repository_association
            when :owners
              repo_owners
            when :starrers
              repo_starrers
            end
          end

          def repo_starrers
            return [] unless message.schema == DELETE_EVENT

            with_read do
              starrer_ids = Star.repositories.where(starrable_id: deleted_repo_id).pluck(:user_id)
              starrer_ids.each_slice(1000).flat_map do |ids|
                User.where(id: ids)
              end
            end
          end

          def repo_owners
            actor_ids = case message.schema
            when TRANSFER_EVENT
              transfer_actor_ids
            when DELETE_EVENT
              deleted_repo_owner_id || actor_id
            else
              actor_id || repository_owner_id
            end

            with_read { User.where(id: actor_ids) }
          end

          def deleted_repo_id
            message.value.dig(:deleted_repository, :id)
          end

          def deleted_repo_owner_id
            message.value.dig(:deleted_repository, :owner_id, :value)
          end

          def deleted_repo_visibility
            message.value.dig(:deleted_repository, :visibility)
          end

          private

          def transfer_actor_ids
            new_owner_id = message.value.dig(:target, :id)
            previous_owner_id = message.value.dig(:previous_owner, :id)
            [new_owner_id, previous_owner_id]
          end

          def actor_id
            message.value.dig(:actor, :id)
          end

          def repository_owner_id
            repo_id = message.value.dig(:repository, :id) || message.value.dig(:repository_id)

            raise ActiveRecord::RecordNotFound if repo_id.nil?

            repository = with_read { Repositories::Public.get_active_or_deleted!(repo_id) }
            repository.owner_id
          rescue ActiveRecord::RecordNotFound
            repo_section = message.value.dig(:repository) ||
                            message.value.dig(:restored_repository)
            repo_section&.dig(:owner, :id)
          end
        end
      end
    end
  end
end
