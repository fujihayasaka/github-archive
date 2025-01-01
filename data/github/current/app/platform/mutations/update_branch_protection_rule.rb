# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateBranchProtectionRule < Platform::Mutations::Base
      description "Update a branch protection rule"

      minimum_accepted_scopes ["public_repo"]

      argument :branch_protection_rule_id, ID, "The global relay id of the branch protection rule to be updated.", required: true, loads: Objects::BranchProtectionRule, as: :protected_branch

      argument :pattern, String, "The glob-like pattern used to determine matching branches.", required: false
      argument :requires_approving_reviews, Boolean, "Are approving reviews required to update matching branches.", required: false
      argument :required_approving_review_count, Integer, "Number of approving reviews required to update matching branches.", required: false
      argument :requires_commit_signatures, Boolean, "Are commits required to be signed.", required: false
      argument :requires_linear_history, Boolean, "Are merge commits prohibited from being pushed to this branch.", required: false
      argument :blocks_creations, Boolean, "Is branch creation a protected operation.", required: false
      argument :allows_force_pushes, Boolean, "Are force pushes allowed on this branch.", required: false
      argument :allows_deletions, Boolean, "Can this branch be deleted.", required: false
      argument :is_admin_enforced, Boolean, "Can admins override branch protection.", required: false
      argument :requires_status_checks, Boolean, "Are status checks required to update matching branches.", required: false
      argument :requires_strict_status_checks, Boolean, "Are branches required to be up to date before merging.", required: false
      argument :requires_code_owner_reviews, Boolean, "Are reviews from code owners required to update matching branches.", required: false
      argument :dismisses_stale_reviews, Boolean, "Will new commits pushed to matching branches dismiss pull request review approvals.", required: false
      argument :restricts_review_dismissals, Boolean, "Is dismissal of pull request reviews restricted.", required: false
      argument :review_dismissal_actor_ids, [ID], "A list of User, Team, or App IDs allowed to dismiss reviews on pull requests targeting matching branches.", required: false
      argument :bypass_pull_request_actor_ids, [ID], "A list of User, Team, or App IDs allowed to bypass pull requests targeting matching branches.", required: false
      argument :bypass_force_push_actor_ids, [ID], "A list of User, Team, or App IDs allowed to bypass force push targeting matching branches.", required: false
      argument :restricts_pushes, Boolean, "Is pushing to matching branches restricted.", required: false
      argument :push_actor_ids, [ID], "A list of User, Team, or App IDs allowed to push to matching branches.", required: false
      argument :required_status_check_contexts, [String], "List of required status check contexts that must pass for commits to be accepted to matching branches.", required: false
      argument :required_status_checks, [Inputs::RequiredStatusCheckInput], "The list of required status checks", required: false
      argument :requires_deployments, Boolean, "Are successful deployments required before merging.", required: false
      argument :required_deployment_environments, [String], "The list of required deployment environments", required: false
      argument :requires_conversation_resolution, Boolean, "Are conversations required to be resolved before merging.", required: false
      argument :requires_merge_queue, Boolean, "Are merges to this branch managed through a merge queue.", required: false, visibility: :internal
      argument :merge_queue_max_entries_to_merge, Integer, "The maximum number of passing queued PRs to merge in a single merge operation.", required: false, visibility: :internal
      argument :merge_queue_min_entries_to_merge, Integer, "The minimum number of passing queued PRs to merge in a single merge operation.", required: false, visibility: :internal
      argument :merge_queue_min_entries_to_merge_wait_time, Integer, "The time (in minutes) to wait for min entries to merge requirement to be met.", required: false, visibility: :internal
      argument :merge_queue_max_group_size, Integer, "Maximum number of entries per merge group.", required: false, visibility: :internal, deprecated: {
        start_date: Date.new(2023, 9, 14),
        reason: "No longer in use.",
        superseded_by: "Use `mergeQueueMaxEntriesToMerge` instead.",
        owner: "github/merge_queue"
      }
      argument :merge_queue_check_run_retries, Integer, "Limit of retries for failed check runs on queued entries.", required: false, visibility: :internal
      argument :merge_queue_merge_method, Enums::PullRequestMergeMethod, "Merge method used by the merge queue.", required: false, visibility: :internal
      argument :merge_queue_max_entries_to_build, Integer, "The maximum number of queued entries (PRs) to create queue refs for which effectively controls how many queued PRs are building at the same time in the queue.", required: false, visibility: :internal
      argument :merge_queue_check_response_timeout, Integer, "The time (in minutes) that a required status check must report a conclusion within; considered failing if not reported by this time.", required: false, visibility: :internal
      argument :merge_queue_merging_strategy, Enums::MergeQueueMergingStrategy, "Merging Strategy for merge queue.", required: false, visibility: :internal
      argument :ignore_approvals_from_contributors, Boolean, "Whether approvals from users that have contributed to a pull request by pushing to its branch should be ignored.", required: false, visibility: :internal
      argument :require_last_push_approval, Boolean, "Whether the most recent push must be approved by someone other than the person who pushed it", required: false
      argument :lock_branch, Boolean, "Whether to set the branch as read-only. If this is true, users will not be able to push to the branch.", required: false
      argument :lock_allows_fetch_and_merge, Boolean, "Whether users can pull changes from upstream when the branch is locked. Set to `true` to allow fork syncing. Set to `false` to prevent fork syncing.", required: false

      field :branch_protection_rule, Objects::BranchProtectionRule, "The newly created BranchProtectionRule.", null: true

      include Shared::ModifyBranchProtectionRule

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, protected_branch:, **inputs)
        protected_branch.async_repository.then do |repository|
          permission.async_owner_if_org(repository).then do |org|
            permission.access_allowed? :update_branch_protection, resource: repository, current_repo: repository, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true
          end
        end
      end

      def resolve(protected_branch:, **inputs)
        protected_branch.async_repository.then do |repository|
          ensure_repo_writable!(repository, context:, operation: :updating)

          protected_branch.name = inputs[:pattern] unless inputs[:pattern].nil?

          update_branch_protection_rule(protected_branch, inputs, context, entry_point: :graphql_api_update_branch_protection_rule_mutation)
        end
      end
    end
  end
end
