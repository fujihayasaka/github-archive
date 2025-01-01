# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class DeleteBranchProtectionRule < Platform::Mutations::Base
      description "Delete a branch protection rule"

      minimum_accepted_scopes ["public_repo"]

      argument :branch_protection_rule_id, ID, "The global relay id of the branch protection rule to be deleted.", required: true, loads: Objects::BranchProtectionRule, as: :protected_branch

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
          ensure_repo_writable!(repository, context:, operation: :deleting)

          protected_branch.destroy_with_args(entry_point: :graphql_api_branch_protection_rule_delete_mutation)

          {}
        end
      end
    end
  end
end
