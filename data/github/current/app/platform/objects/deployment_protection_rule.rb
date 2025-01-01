# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class DeploymentProtectionRule < Platform::Objects::Base
      description "A protection rule."
      model_name "Gate"

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, protection_rule)
        protection_rule.async_environment.then do |environment|
          permission.async_repo_and_org_owner(environment).then do |repo, org|
            permission.access_allowed?(:read_actions, resource: repo, current_repo: repo, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
          end
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, protection_rule)
        protection_rule.async_environment.then do |environment|
          permission.load_repo_and_owner(environment).then do |repo|
            repo.resources.actions.async_readable_by?(permission.viewer)
          end
        end
      end

      scopeless_tokens_as_minimum

      database_id_field

      field :type, Enums::DeploymentProtectionRuleType, description: "The type of protection rule.", null: false

      field :timeout, Integer, description: "The timeout in minutes for this protection rule.", null: false

      field :reviewers, Connections.define(Unions::DeploymentReviewer), description: "The teams or users that can review the deployment", connection: true, null: false

      field :prevent_self_review, Boolean, description: "Whether deployments to this environment can be approved by the user who created the deployment.", null: true

      def reviewers(**arguments)
        @object.async_gate_approvers.then do |approvers|
          Promise.all(approvers.map(&:async_approver)).then do |approvers|
            ArrayWrapper.new(approvers)
          end
        end
      end
    end
  end
end
