# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class BranchProtectionRuleConflict < Platform::Objects::Base
      minimum_accepted_scopes ["public_repo"]

      description "A conflict between two branch protection rules."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(_permission, _conflict)
        # To access a branch protection rule conflict, the caller already needs to get permissions to read a branch protection rule
        # and we don't have finer-grained permissions for conflicts.
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.belongs_to_repository(object.branch_protection_rule)
      end

      field :branch_protection_rule, BranchProtectionRule,
        description: "Identifies the branch protection rule.",
        method: :branch_protection_rule,
        null: true

      field :ref, Ref,
        description: "Identifies the branch ref that has conflicting rules",
        method: :ref,
        null: true

      field :conflicting_branch_protection_rule, BranchProtectionRule,
        description: "Identifies the conflicting branch protection rule.",
        method: :conflicting_branch_protection_rule,
        null: true
    end
  end
end
