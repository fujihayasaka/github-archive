# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class DequeuePullRequest < Platform::Mutations::Base
      description "Remove a pull request from the merge queue."
      visibility :public, environments: [:dotcom, :enterprise]

      minimum_accepted_scopes ["public_repo"]

      argument :id, ID, "The ID of the pull request to be dequeued.", required: true, loads: Objects::PullRequest, as: :pull_request

      field :merge_queue_entry, Objects::MergeQueueEntry, "The merge queue entry of the dequeued pull request.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, pull_request:, **inputs)
        permission.async_repo_and_org_owner(pull_request).then do |repo, org|
          permission.access_allowed?(:dequeue_pull_request,
            repo: repo,
            resource: pull_request,
            current_org: org,
            allow_integrations: true,
            allow_user_via_granular_actor: true,
          )
        end
      end

      def resolve(pull_request:, **inputs)
        raise Errors::MergeQueue::NotEnabled unless GitHub.merge_queues_enabled?

        repository = pull_request.repository
        raise Errors::MergeQueue::NotEnabledForRepository.new(repository) unless repository.merge_queue_enabled?

        context[:permission].authorize_content(:pull_request, :dequeue, repository: repository)

        branch = pull_request.base_ref_name
        merge_queue = MergeQueue.for(repository: repository, branch: branch)
        raise Errors::MergeQueue::NotFoundForBranch.new(branch) unless merge_queue

        dequeued_entry = merge_queue.entry_for(pull_request: pull_request)

        dequeued = begin
          merge_queue.dequeue(
            pull_request: pull_request,
            dequeuer: context[:viewer],
            raise_group_locked_error: true)
        rescue MergeQueues::Errors::GroupLocked
          raise Errors::MergeQueue::NotRemovedFromQueueBecauseGroupLocked.new(pull_request)
        end
        raise Errors::MergeQueue::NotRemovedFromQueue.new(pull_request) unless dequeued

        {
          merge_queue_entry: dequeued_entry
        }

      rescue ActiveRecord::RecordInvalid => e
        raise Errors::Unprocessable.new(e.record.errors.full_messages.to_sentence)
      end
    end
  end
end
