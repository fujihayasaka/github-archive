# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class EnqueuePullRequest < Platform::Mutations::Base
      description "Add a pull request to the merge queue."
      visibility :public, environments: [:dotcom, :enterprise]

      minimum_accepted_scopes ["public_repo"]

      argument :pull_request_id, ID, "The ID of the pull request to enqueue.", required: true, loads: Objects::PullRequest, as: :pull_request
      argument :jump, Boolean, "Add the pull request to the front of the queue.", required: false
      argument :expected_head_oid, Scalars::GitObjectID, "The expected head OID of the pull request.", required: false

      field :merge_queue_entry, Objects::MergeQueueEntry, "The merge queue entry for the enqueued pull request.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, pull_request:, **inputs)
        permission.async_repo_and_org_owner(pull_request).then do |repo, org|
          permission.access_allowed?(:enqueue_pull_request,
            repo: repo,
            resource: pull_request,
            current_org: org,
            allow_integrations: true,
            allow_user_via_granular_actor: true,
          )
        end
      end

      def resolve(pull_request:, jump: false, expected_head_oid: nil, **inputs)
        raise Errors::MergeQueue::NotEnabled unless GitHub.merge_queues_enabled?

        repository = pull_request.repository
        raise Errors::MergeQueue::NotEnabledForRepository.new(repository) unless repository.merge_queue_enabled?

        context[:permission].authorize_content(:pull_request, :enqueue, repository: repository)

        branch = pull_request.base_ref_name
        merge_queue = MergeQueue.for(repository: repository, branch: branch)
        raise Errors::MergeQueue::NotFoundForBranch.new(branch) unless merge_queue

        if expected_head_oid
          raise Errors::MergeQueue::PullRequestHeadOidMismatch.new(pull_request) unless pull_request.head_sha == expected_head_oid
        end

        entry = merge_queue.enqueue!(
          pull_request: pull_request,
          enqueuer: context[:viewer],
          solo: false,
          jump_queue: jump,
        )

        {
          merge_queue_entry: entry
        }

      rescue ActiveRecord::RecordInvalid => e
        raise Errors::Unprocessable.new(e.record.errors.full_messages.to_sentence)
      end
    end
  end
end
