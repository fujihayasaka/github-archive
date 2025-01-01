# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class BranchProtectionRule < Platform::Objects::Base
      minimum_accepted_scopes ["public_repo"]

      description "A branch protection rule."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, protection_rule)
        if permission&.viewer&.feature_enabled?(:batch_authzd_branch_protection_checks) || GitHub.flipper[:batch_authzd_branch_protection_checks].enabled?
          permission.async_repo_and_org_owner(protection_rule).then do |repo, org|
            promise = repo&.async_can_edit_repo_protections?(permission.viewer) || Promise.resolve(nil)
            promise.then do |_allowed| # preload the authzd check asynchronously so it is cached when access_allowed? checks it
              permission.access_allowed?(:read_branch_protection, resource: repo, current_repo: repo, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
            end
          end
        else
          permission.async_repo_and_org_owner(protection_rule).then do |repo, org|
            permission.access_allowed?(:read_branch_protection, resource: repo, current_repo: repo, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
          end
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.belongs_to_repository(object)
      end

      implements_node templates: [[:bpr, :repository_id, :id]], as: "BPR", ready_date: Platform::Helpers::GlobalId::COHORT_3 do |branch_protection_rule|
        { prefix: :bpr, repository_id: branch_protection_rule.repository_id, id: branch_protection_rule.id }
      end

      def self.load_from_next_global_id(parsed_id)
        load_from_global_id(parsed_id.id)
      end

      def self.load_from_global_id(id)
        Platform::Objects.async_find_record_by_id(::ProtectedBranch, id)
      end

      database_id_field

      field :pattern, String,
        description: "Identifies the protection rule pattern.",
        null: false

      def pattern
        @object.name.dup.force_encoding("utf-8")
      end

      field :repository, Repository,
        description: "The repository associated with this branch protection rule.",
        method: :async_repository,
        null: true

      field :creator, resolver: Resolvers::ActorCreator,
        description: "The actor who created this branch protection rule."

      field :is_admin_enforced, Boolean,
        description: "Can admins override branch protection.",
        method: :admin_enforced?,
        null: false

      field :requires_approving_reviews, Boolean,
        description: "Are approving reviews required to update matching branches.",
        method: :pull_request_reviews_enabled?,
        null: false

      field :required_approving_review_count, Integer,
        description: "Number of approving reviews required to update matching branches.",
        null: true

      def required_approving_review_count
        return unless @object.pull_request_reviews_enabled?
        @object.required_approving_review_count
      end

      field :dismisses_stale_reviews, Boolean,
        description: "Will new commits pushed to matching branches dismiss pull request review approvals.",
        method: :dismiss_stale_reviews_on_push?,
        null: false

      field :restricts_review_dismissals, Boolean,
        description: "Is dismissal of pull request reviews restricted.",
        method: :authorized_dismissal_actors_only,
        null: false

      field :review_dismissal_allowances,
        type: Connections::ReviewDismissalAllowance,
        resolver: Resolvers::ReviewDismissalAllowances,
        description: "A list review dismissal allowances for this branch protection rule.",
        null: false,
        connection: true

      field :bypass_pull_request_allowances,
        type: Connections.define(Objects::BypassPullRequestAllowance),
        description: "A list of actors able to bypass PRs for this branch protection rule.",
        null: false,
        connection: true
      def bypass_pull_request_allowances
        @object.branch_actor_allowances_for_policy(:pull_request).scoped
      end

      field :bypass_force_push_allowances,
      type: Connections.define(Objects::BypassForcePushAllowance),
        description: "A list of actors able to force push for this branch protection rule.",
        null: false,
        connection: true
      def bypass_force_push_allowances
        @object.branch_actor_allowances_for_policy(:force_push).scoped
      end

      field :requires_status_checks, Boolean,
        description: "Are status checks required to update matching branches.",
        method: :required_status_checks_enabled?,
        null: false

      field :requires_code_owner_reviews, Boolean,
        description: "Are reviews from code owners required to update matching branches.",
        null: false

      def requires_code_owner_reviews
        @object.async_repository.then do |repository|
          Promise.all([repository.async_internal_repository, repository.async_business, repository.async_plan_customer]).then do
            @object.require_code_owner_review?
          end
        end
      end

      field :requires_deployments, Boolean,
        description: "Does this branch require deployment to specific environments before merging",
        null: false,
        method: :required_deployments_enabled?

      field :required_deployment_environments, [String, null: true],
        description: "List of required deployment environments that must be deployed successfully to update matching branches",
        null: true
      def required_deployment_environments
        @object.async_required_deployments.then do |required_deployments|
          required_deployments.map(&:environment)
        end
      end

      field :requires_conversation_resolution, Boolean,
        description: "Are conversations required to be resolved before merging.",
        null: false,
        method: :required_review_thread_resolution_enabled?

      field :requires_strict_status_checks, Boolean,
        description: "Are branches required to be up to date before merging.",
        method: :strict_required_status_checks_policy,
        null: false

      field :required_status_check_contexts, [String, null: true],
        description: "List of required status check contexts that must pass for commits to be accepted to matching branches.",
        null: true

      def required_status_check_contexts
        @object.async_required_status_checks.then do |required_status_checks|
          required_status_checks.map(&:context)
        end
      end

      field :required_status_checks, [Objects::RequiredStatusCheckDescription],
        description: "List of required status checks that must pass for commits to be accepted to matching branches.",
        null: true

      def required_status_checks
        @object.async_required_status_checks
      end

      field :restricts_pushes, Boolean,
        description: "Is pushing to matching branches restricted.",
        method: :authorized_actors_only,
        null: false

      field :push_allowances,
        type: Connections::PushAllowance,
        resolver: Resolvers::PushAllowances,
        description: "A list push allowances for this branch protection rule.",
        null: false,
        connection: true

      field :requires_commit_signatures, Boolean,
        description: "Are commits required to be signed.",
        method: :required_signatures_enabled?,
        null: false

      field :requires_linear_history, Boolean,
        description: "Are merge commits prohibited from being pushed to this branch.",
        method: :required_linear_history_enabled?,
        null: false

      field :blocks_creations, Boolean,
        description: "Is branch creation a protected operation.",
        method: :create_protected_enabled?,
        null: false

      field :allows_force_pushes, Boolean,
        description: "Are force pushes allowed on this branch.",
        null: false

      def allows_force_pushes
        !@object.block_force_pushes_enabled?
      end

      field :allows_deletions, Boolean,
        description: "Can this branch be deleted.",
        null: false

      def allows_deletions
        !@object.block_deletions_enabled?
      end

      field :matching_refs, Connections::Ref,
        resolver: Resolvers::Refs,
        description: "Repository refs that are protected by this rule",
        null: false,
        connection: true

      field :branch_protection_rule_conflicts, Connections.define(Objects::BranchProtectionRuleConflict),
        description: "A list of conflicts matching branches protection rule and other branch protection rules",
        connection: true,
        null: false

      field :requires_merge_queue, Boolean,
        description: "Are merges to this branch managed through a merge queue.",
        method: :merge_queue_enabled?,
        visibility: :internal,
        null: false

      field :merge_queue_max_entries_to_merge, Integer,
        description: "The maximum number of passing queued PRs to merge in a single merge operation.",
        visibility: :internal,
        null: true

      def merge_queue_max_entries_to_merge
        @object.async_merge_queue.then do |merge_queue|
          merge_queue&.max_entries_to_merge
        end
      end

      field :merge_queue_min_entries_to_merge, Integer,
        description: "The minimum number of passing queued PRs to merge in a single merge operation.",
        visibility: :internal,
        null: true

      def merge_queue_min_entries_to_merge
        @object.async_merge_queue.then do |merge_queue|
          merge_queue&.min_entries_to_merge
        end
      end

      field :merge_queue_min_entries_to_merge_wait_time, Integer,
        description: "The time (in minutes) to wait for min entries to merge requirement to be met.",
        visibility: :internal,
        null: true

      def merge_queue_min_entries_to_merge_wait_time
        @object.async_merge_queue.then do |merge_queue|
          merge_queue&.min_entries_to_merge_wait_minutes
        end
      end

      field :merge_queue_max_group_size, Integer,
        description: "Maximum number of entries per merge group.",
        visibility: :internal,
        null: true,
        deprecated: {
          start_date: Date.new(2023, 9, 14),
          reason: "No longer in use",
          superseded_by: :merge_queue_max_entries_to_merge,
          owner: "github/merge_queue"
        }

      def merge_queue_max_group_size
        merge_queue_max_entries_to_merge
      end

      field :merge_queue_check_run_retries, Integer,
        description: "Limit of retries for failed check runs on queued entries.",
        visibility: :internal,
        null: true

      def merge_queue_check_run_retries
        @object.async_merge_queue.then do |merge_queue|
          merge_queue&.check_run_retries_limit
        end
      end

      field :merge_queue_max_entries_to_build, Integer,
        description: "The maximum number of queued entries (PRs) to create queue refs for which effectively controls how many queued PRs are building at the same time in the queue.",
        visibility: :internal,
        null: true

      def merge_queue_max_entries_to_build
        @object.async_merge_queue.then do |merge_queue|
          merge_queue&.max_entries_to_build
        end
      end


      field :merge_queue_check_response_timeout, Integer,
        description: "The time (in minutes) that a required status check must report a conclusion within; considered failing if not reported by this time.",
        visibility: :internal,
        null: true

      def merge_queue_check_response_timeout
        @object.async_merge_queue.then do |merge_queue|
          # default to 1 minute if 0
          merge_queue&.check_response_timeout_minutes == 0 ? 1 : merge_queue&.check_response_timeout_minutes
        end
      end


      field :merge_queue_merging_strategy, Enums::MergeQueueMergingStrategy,
        description: "Configured merging strategy. If failing entries are allowed to merge if they are with a passing entry then 'HEADGREEN' if all must pass 'ALLGREEN'.",
        visibility: :internal,
        null: true

      def merge_queue_merging_strategy
        @object.async_merge_queue.then do |merge_queue|
          merge_queue&.merging_strategy
        end
      end

      field :merge_queue_merge_method, Enums::PullRequestMergeMethod,
        description: "Merge method used by the merge queue.",
        visibility: :internal,
        null: true

      def merge_queue_merge_method
        @object.async_merge_queue.then do |merge_queue|
          merge_queue&.merge_method&.to_sym
        end
      end

      field :ignore_approvals_from_contributors, Boolean,
        description: "Whether approvals from users that have contributed to a pull request by pushing to its branch should be ignored.",
        visibility: :internal,
        null: false

      field :require_last_push_approval, Boolean,
        description: "Whether the most recent push must be approved by someone other than the person who pushed it",
        null: false

      field :lock_branch, Boolean,
        description: "Whether to set the branch as read-only. If this is true, users will not be able to push to the branch.",
        method: :lock_branch_enabled?,
        null: false

      field :lock_allows_fetch_and_merge, Boolean,
        description: "Whether users can pull changes from upstream when the branch is locked. Set to `true` to allow fork syncing. Set to `false` to prevent fork syncing.",
        null: false

      def branch_protection_rule_conflicts
        @object.async_repository.then do |repository|
          Platform::Loaders::BranchProtectionRule::MatchesAndConflicts.load(repository, @object).then do |information|
            conflict_information = information[:conflicts].map do |data|
              Platform::Models::BranchProtectionRuleConflict.new(@object, data[:ref], data[:conflicting_protected_branch])
            end

            ArrayWrapper.new(conflict_information)
          end
        end
      end
    end
  end
end
