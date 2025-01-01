# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class RemovePullRequestFromMergeQueue < Platform::Mutations::Base
      description "Removes a pull request from a merge queue"

      minimum_accepted_scopes ["public_repo"]
      feature_flag :merge_queue

      DeprecationNotice = {
        start_date: Date.new(2022, 5, 19),
        reason: "PRs are removed from the merge queue for the base branch, the `branch` argument is now a no-op",
        owner: "jhunschejones",
        superseded_by: nil,
      }

      argument :pull_request_id, ID, "The Node ID of the pull request to remove.", required: true, loads: Objects::PullRequest, as: :pull_request
      argument :branch, String, "Which branch's merge queue we want to remove this pull request from.", required: false, deprecated: DeprecationNotice

      field :merge_queue, Objects::MergeQueue, "The updated merge queue", null: true

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

      def resolve(pull_request:, branch: nil, **inputs)
        raise Errors::MergeQueue::NotEnabled unless GitHub.merge_queues_enabled?

        repository = pull_request.repository

        unless MergeQueues.private_apis_available?(repository)
          raise Errors::MergeQueue::NotEnabledForRepository.new(repository)
        end

        context[:permission].authorize_content(:pull_request, :dequeue, repository: repository)

        # NOTE: we are not using the branch argument per https://github.com/github/pull-requests/issues/2909
        branch = pull_request.base_ref
        merge_queue = MergeQueue.for(repository: repository, branch: branch)
        raise Errors::MergeQueue::NotFoundForBranch.new(branch) unless merge_queue

        dequeued = begin
          merge_queue.dequeue(pull_request: pull_request, dequeuer: context[:viewer], raise_group_locked_error: true)
        rescue MergeQueues::Errors::GroupLocked
          raise Errors::MergeQueue::NotRemovedFromQueueBecauseGroupLocked.new(pull_request)
        end
        raise Errors::MergeQueue::NotRemovedFromQueue.new(pull_request) unless dequeued

        {
          merge_queue: merge_queue
        }
      end
    end
  end
end
