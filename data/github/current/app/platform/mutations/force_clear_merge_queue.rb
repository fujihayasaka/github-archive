# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class ForceClearMergeQueue < Platform::Mutations::Base
      description "Internal endpoint used to clear the merge queue."

      visibility :internal
      minimum_accepted_scopes ["public_repo"]
      feature_flag :merge_queue

      argument :repository_id, ID, "The Node ID of the repository with the merge queue.", required: true,
        loads: Objects::Repository, as: :repository
      argument :branch, String, "The name of the protected branch for the merge queue. Default to the repository's default branch.", required: false
      argument :remove_queue_entries, Boolean, "Whether to remove all merge queue entries. Default to false.", required: false, deprecated: {
        start_date: Date.new(2023, 05, 05),
        reason: "removing merge groups without removing entries is no longer a supported action",
        superseded_by: nil,
        owner: "github/merge_queue"
      }

      field :merge_queue, Objects::MergeQueue, "The merge queue whose merge group was unlocked.",
        null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, repository:, **inputs)
        permission.async_owner_if_org(repository).then do |org|
          permission.access_allowed?(:force_clear_merge_queue,
            resource: repository,
            current_repo: repository,
            current_org: org,
            allow_integrations: true,
            allow_user_via_granular_actor: true,
          )
        end
      end

      def resolve(repository:, branch: nil, remove_queue_entries: false)
        raise Errors::MergeQueue::NotEnabled unless GitHub.merge_queues_enabled?

        unless MergeQueues.private_apis_available?(repository)
          raise Errors::MergeQueue::NotEnabledForRepository.new(repository)
        end

        context[:permission].authorize_content(:merge_queue, :force_clear_merge_queue, repository: repository)

        branch = repository.default_branch if branch.nil?
        merge_queue = repository.merge_queue_for(branch: branch)
        raise Errors::MergeQueue::NotFoundForBranch.new(branch) unless merge_queue

        merge_queue.force_clear(actor: context[:viewer], async: false)

        { merge_queue: merge_queue }
      end
    end
  end
end
