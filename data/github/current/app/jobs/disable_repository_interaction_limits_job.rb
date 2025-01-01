# typed: true
# frozen_string_literal: true

class DisableRepositoryInteractionLimitsJob < ApplicationJob
  queue_as :disable_repository_interaction_limits

  retry_on_dirty_exit

  BATCH_SIZE = 10_000

  def perform(owner_id, actor_id)
    return unless GitHub.interaction_limits_enabled?

    owner = User.find(owner_id)
    actor = User.find(actor_id)
    owner.repositories.public_scope.find_in_batches(batch_size: BATCH_SIZE) do |batch|
      Repository.throttle do
        batch.each do |repo|
          with_write do
            RepositoryInteractionAbility.disable_active_local_limit_for(repo, actor)
          end
        end
      end
    end
  end
end
