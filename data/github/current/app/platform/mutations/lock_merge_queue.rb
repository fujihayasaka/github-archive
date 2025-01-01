# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class LockMergeQueue < Platform::Mutations::Base
      description "Locks a merge queue for deployment and returns the merge head oid"

      minimum_accepted_scopes ["public_repo"]
      feature_flag :merge_queue

      argument :repository_id, ID, "The Node ID of the repository with the merge queue.", required: true, loads: Objects::Repository, as: :repository
      argument :branch, String, "Which branch's merge queue to lock.", required: false

      field :head_oid, Scalars::GitObjectID, "OID for the merge head of the group.", null: true
      field :head_ref, String, "Ref for the merge head of the group.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, repository:, **inputs)
        permission.async_owner_if_org(repository).then do |org|
          permission.access_allowed?(:lock_merge_queue,
            resource: repository,
            current_repo: repository,
            current_org: org,
            allow_integrations: true,
            allow_user_via_granular_actor: true,
          )
        end
      end

      def resolve(repository:, branch: nil, **inputs)
        context[:permission].authorize_content(:merge_queue, :lock, repository: repository)

        unless MergeQueues.private_apis_available?(repository)
          return {}
        end

        branch ||= repository.default_branch
        merge_queue = repository.merge_queue_for(branch: branch)
        raise Errors::MergeQueue::NotFoundForBranch.new(branch) unless merge_queue

        unless merge_queue.requires_deployments_before_merging?
          raise Errors::MergeQueue::DeploymentsNotRequired.new(branch)
        end

        head_oid = T.let(nil, T.nilable(String))
        head_ref = T.let(nil, T.nilable(String))

        if queue_entry = MergeQueues.lock_best_entry!(repository:, branch: merge_queue.branch, actor: context[:viewer])
          head_oid = queue_entry.head_sha
          head_ref = queue_entry.qualified_head_ref
        end

        { head_oid:, head_ref: }
      rescue MergeQueues::Errors::Base => e
        raise Errors::Unprocessable.new(e.message)
      end
    end
  end
end
