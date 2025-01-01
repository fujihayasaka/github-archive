# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UnlockMergeGroup < Platform::Mutations::Base
      description "Unlock for a protected branch's merge queue. This will keep " \
        "the group and its entries."

      minimum_accepted_scopes ["public_repo"]
      feature_flag :merge_queue

      argument :repository_id, ID, "The Node ID of the repository with the merge queue.", required: true,
        loads: Objects::Repository, as: :repository
      argument :branch, String, "The name of the protected branch for the merge queue. Default to the repository's default branch.", required: false

      field :merge_queue, Objects::MergeQueue, "The merge queue whose merge group was unlocked.",
        null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, repository:, **inputs)
        permission.async_owner_if_org(repository).then do |org|
          permission.access_allowed?(:unlock_merge_group,
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

        context[:permission].authorize_content(:merge_queue, :unlock_merge_group, repository: repository)

        branch = repository.default_branch if branch.nil?
        merge_queue = repository.merge_queue_for(branch: branch)
        raise Errors::MergeQueue::NotFoundForBranch.new(branch) unless merge_queue

        unless merge_queue.requires_deployments_before_merging?
          raise Errors::MergeQueue::DeploymentsNotRequired.new(branch)
        end

        result = begin
          MergeQueues.unlock!(
            repository:,
            branch:,
            merge_queue:,
            actor: context[:viewer],
          )
        rescue ActiveRecord::RecordInvalid => exception
          Failbot.report(exception)
          raise Errors::Unprocessable.new("Could not unlock #{branch} merge queue.")
        end

        case result
        when MergeQueues::Service::Unlock::Result::NextGroupEmpty
          raise Errors::Unprocessable.new(
            "Could not unlock as there is no current merge group " \
            "for #{branch}."
          )
        when MergeQueues::Service::Unlock::Result::NextGroupNotLocked
          raise Errors::Unprocessable.new(
            "Could not unlock as there is no locked merge " \
            "group for #{branch}."
          )
        when MergeQueues::Service::Unlock::Result::Success
          { merge_queue: }
        else
          T.absurd(result)
        end
      end
    end
  end
end
