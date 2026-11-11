# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class RefUpdateRule < Platform::Objects::Base
      minimum_accepted_scopes ["public_repo"]

      description "Branch protection rules that are enforced on the viewer."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, protection_rule)
        permission.async_repo_and_org_owner(protection_rule).then do |repo, org|
          permission.access_allowed?(:get_ref, resource: repo, current_repo: repo, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.belongs_to_repository(object)
      end

      field :pattern, String,
        description: "Identifies the protection rule pattern.",
        null: false

      def pattern
        @object.name.dup.force_encoding("utf-8")
      end

      field :required_approving_review_count, Integer,
        description: "Number of approving reviews required to update matching branches.",
        null: true

      def required_approving_review_count
        @object.async_repository.then do |repo|
          repo.async_owner.then do
            next 0 unless @object.required_review_policy_enforced_for?(actor: context[:viewer])
            @object.required_approving_review_count
          end
        end
      end

      field :recommended_approving_review_count, Integer,
        description: "Number of approving reviews recommended to update matching branches.",
        null: true, required_capabilities: [:mobile_only_schema_mask]

      def recommended_approving_review_count
        @object.async_repository.then do |repo|
          repo.async_owner.then do
            @object.required_approving_review_count
          end
        end
      end

      field :required_status_check_contexts, [String, null: true],
        description: "List of required status check contexts that must pass for commits to be accepted to matching branches.",
        null: true

      def required_status_check_contexts
        @object.async_repository.then do |repo|
          repo.async_owner.then do
            next [] unless @object.required_status_checks_enforced_for?(actor: context[:viewer])

            @object.async_required_status_checks.then do |required_status_checks|
              required_status_checks.map(&:context)
            end
          end
        end
      end

      field :requires_signatures, Boolean,
        description: "Are commits required to be signed.",
        null: false

      def requires_signatures
        @object.async_repository.then do |repo|
          repo.async_owner.then do
            @object.required_signatures_enforced_for?(actor: context[:viewer])
          end
        end
      end

      field :requires_linear_history, Boolean, description: "Are merge commits prohibited from being pushed to this branch.", null: false

      def requires_linear_history
        @object.async_repository.then do |repo|
          repo.async_owner.then do
            @object.required_linear_history_enforced_for?(actor: context[:viewer])
          end
        end
      end

      field :viewer_can_push, Boolean, description: "Can the viewer push to the branch", null: false

      def viewer_can_push
        @object.push_authorized?(context[:viewer])
      end

      field :allows_force_pushes, Boolean, description: "Are force pushes allowed on this branch.", null: false

      def allows_force_pushes
        !@object.block_force_pushes_enabled?
      end

      field :allows_deletions, Boolean, description: "Can this branch be deleted.", null: false

      def allows_deletions
        !@object.block_deletions_enabled?
      end

      field :blocks_creations, Boolean,
        description: "Can matching branches be created.",
        null: false

      def blocks_creations
        @object.create_protected_enabled?
      end

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

      field :viewer_allowed_to_dismiss_reviews, Boolean,
        description: "Is the viewer allowed to dismiss reviews.",
        null: false

      def viewer_allowed_to_dismiss_reviews
        @object.async_review_dismissal_allowances.then do
          if @object.restricted_dismissed_reviews?
            @object.review_dismissable_by?(context[:viewer])
          else
            @object.push_authorized?(context[:viewer])
          end
        end
      end

      field :requires_conversation_resolution, Boolean,
        description: "Are conversations required to be resolved before merging.",
        null: false

      def requires_conversation_resolution
        @object.required_review_thread_resolution_enforced_for?(actor: context[:viewer])
      end
    end
  end
end
