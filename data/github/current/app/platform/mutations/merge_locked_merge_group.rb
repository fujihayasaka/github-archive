# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class MergeLockedMergeGroup < Platform::Mutations::Base
      description "Merge the current merge group of a merge queue into its protected branch."

      minimum_accepted_scopes ["public_repo"]
      feature_flag :merge_queue

      argument :repository_id, ID, "The Node ID of the repository with the merge queue.", required: true,
        loads: Objects::Repository, as: :repository
      argument :branch, String, "The name of the protected branch to merge changes into.", required: false

      field :merge_queue, Objects::MergeQueue, "The merge queue that was affected by the merge.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, repository:, **inputs)
        permission.async_owner_if_org(repository).then do |org|
          permission.access_allowed?(:merge_locked_merge_group,
            resource: repository,
            current_repo: repository,
            current_org: org,
            allow_integrations: true,
            allow_user_via_granular_actor: true,
          )
        end
      end

      def resolve(repository:, branch: nil)
        raise Errors::MergeQueue::NotEnabled unless GitHub.merge_queues_enabled?

        unless MergeQueues.private_apis_available?(repository)
          raise Errors::MergeQueue::NotEnabledForRepository.new(repository)
        end

        context[:permission].authorize_content(:merge_queue, :merge_locked_merge_group, repository: repository)

        branch ||= repository.default_branch
        merge_queue = repository.merge_queue_for(branch: branch)
        raise Errors::MergeQueue::NotFoundForBranch.new(branch) unless merge_queue

        unless merge_queue.requires_deployments_before_merging?
          raise Errors::MergeQueue::DeploymentsNotRequired.new(branch)
        end

        result = MergeQueues.merge_locked_entry!(repository:, branch: merge_queue.branch, actor: context[:viewer])

        case result
        when MergeQueues::Service::MergeLockedEntry::Result::Success
          { merge_queue: merge_queue }
        when MergeQueues::Service::MergeLockedEntry::Result::MergeError
          raise Errors::Unprocessable.new(result.message)
        when MergeQueues::Service::MergeLockedEntry::Result::NoLockedEntryError
          raise Errors::Unprocessable.new("Cannot merge an unlocked group of pull requests.")
        when MergeQueues::Service::MergeLockedEntry::Result::FailedToAcquireMutex
          raise Errors::Unprocessable.new("Cannot lock queue entries: another process holds a mutex for this queue.")
        else
          T.absurd(result)
        end
      rescue ::MergeQueues::Errors::Base => err
        raise Errors::Unprocessable.new("Could not merge: #{err.message}")
      end
    end
  end
end
