# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class AddPullRequestToMergeQueue < Platform::Mutations::Base
      description "Adds a pull request to a merge queue"

      minimum_accepted_scopes ["public_repo"]
      feature_flag :merge_queue

      DeprecationNotice = {
        start_date: Date.new(2022, 3, 9),
          reason: "PRs are added to the merge queue for the base branch, the `branch` argument is now a no-op",
          owner: "jhunschejones",
          superseded_by: nil,
      }

      argument :pull_request_id, ID, "The Node ID of the pull request to add.", required: true, loads: Objects::PullRequest, as: :pull_request
      argument :branch, String, "Which branch's merge queue to add to.", required: false, deprecated: DeprecationNotice
      argument :solo, Boolean, "Whether to consider this PR for grouping or force a solo merge when the require deployments to succeed before merging branch protection rule is enabled.", required: false
      argument :jump, Boolean, "Whether to jump this PR to the top of the queue.", required: false

      field :pull_request, Objects::PullRequest, "The pull request.", null: true
      field :merge_queue_entry, Objects::MergeQueueEntry, "The newly created merge queue entry", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
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

      def resolve(pull_request:, branch: nil, solo: false, jump: false, **inputs)
        raise Errors::MergeQueue::NotEnabled unless GitHub.merge_queues_enabled?

        repository = pull_request.repository

        unless MergeQueues.private_apis_available?(repository)
          raise Errors::MergeQueue::NotEnabledForRepository.new(repository)
        end

        context[:permission].authorize_content(:pull_request, :enqueue, repository: repository)

        # NOTE: we are not using the branch argument per https://github.com/github/pull-requests/issues/2909
        branch = pull_request.base_ref_name
        merge_queue = MergeQueue.for(repository: repository, branch: branch)
        raise Errors::MergeQueue::NotFoundForBranch.new(branch) unless merge_queue

        # solo merges are only allowed if the requires deployments before merging branch protection is enabled
        if solo && !merge_queue.requires_deployments_before_merging?
          solo = false
        end

        entry = merge_queue.enqueue!(
          pull_request: pull_request,
          enqueuer: context[:viewer],
          solo: solo,
          jump_queue: jump,
        )

        {
          pull_request: pull_request,
          merge_queue_entry: entry
        }

      rescue ActiveRecord::RecordInvalid => e
        raise Errors::Unprocessable.new(e.record.errors.full_messages.to_sentence)
      end
    end
  end
end
