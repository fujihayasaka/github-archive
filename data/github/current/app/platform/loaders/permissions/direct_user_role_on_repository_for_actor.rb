# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    module Permissions
      class DirectUserRoleOnRepositoryForActor < Platform::Loader
        BATCH_SIZE = 1_000

        def self.load(actor_id:, actor_type:, repo_id:)
          self.for(actor_type).load([actor_id, repo_id])
        end

        def initialize(actor_type)
          @actor_type = actor_type
        end

        # entries is an Array of [actor_id, repo_id] that we're trying to look up
        # actor_ids are all ids of type @actor_type
        def fetch(entries)
          results = {}
          entries.uniq.sort.each_slice(BATCH_SIZE).each do |batch|
            user_roles = batch.map do |actor_id, repo_id|
              UserRole.where(actor_id: actor_id, target_id: repo_id)
            end.reduce(:or)

            user_roles = user_roles.includes(:role).where(
              actor_type: @actor_type,
              target_type: Repository)

            user_roles.each do |user_role|
              results[[user_role.actor_id, user_role.target_id]] = user_role
            end
          end
          results
        end
      end
    end
  end
end
