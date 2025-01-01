# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class BypassPullRequestAllowance < Platform::Objects::Base
      description "A user, team, or app who has the ability to bypass a pull request requirement on a protected branch."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, bypass_pull_request_allowance)
        bypass_pull_request_allowance.async_protected_branch.then do |protected_branch|
          permission.typed_can_access?("BranchProtectionRule", protected_branch)
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        object.async_protected_branch.then do |protected_branch|
          permission.typed_can_see?("BranchProtectionRule", protected_branch)
        end
      end

      minimum_accepted_scopes ["public_repo"]

      implements_node templates: [
        [:bpra, :repo_id, :bypass_pull_request_allowance_id]],
        as: "BPRA", ready_date: "1970-01-01" do |bypass_pull_request_allowance|
          bypass_pull_request_allowance.async_protected_branch.then do |protected_branch|
            protected_branch.async_repository.then do |repo|
              {
                    prefix: :bpra,
                    repo_id: repo.id,
                    bypass_pull_request_allowance_id: bypass_pull_request_allowance.id
              }
            end
          end
        end

      field :actor, Unions::BranchActorAllowanceActor, description: "The actor that can bypass.", null: true

      def actor
        @object.async_actor.then do |actor|
          actor.is_a?(::IntegrationInstallation) ? actor.async_integration : actor
        end
      end

      field :branch_protection_rule, BranchProtectionRule,
        "Identifies the branch protection rule associated with the allowed user, team, or app.",
        null: true,
        method: :protected_branch

    end
  end
end
