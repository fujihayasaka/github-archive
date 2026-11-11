# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class DeploymentRequest < Platform::Objects::Base
      description "A request to deploy a workflow run to an environment."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, deployment_request)
        permission.async_repo_and_org_owner(deployment_request.environment).then do |repo, org|
          permission.access_allowed?(:read_actions, resource: repo, current_repo: repo, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, deployment_request)
        permission.load_repo_and_owner(deployment_request.environment).then do |repo|
          repo.resources.actions.async_readable_by?(permission.viewer)
        end
      end

      scopeless_tokens_as_minimum

      field :environment, Objects::Environment, description: "The target environment of the deployment", null: false

      field :reviewers, Connections.define(Unions::DeploymentReviewer), description: "The teams or users that can review the deployment", connection: true, null: false

      field :current_user_can_approve, Boolean, description: "Whether or not the current user can approve the deployment", null: false

      field :wait_timer, Integer, description: "The wait timer in minutes configured in the environment", null: false

      field :wait_timer_started_at, Scalars::DateTime, description: "The wait timer in minutes configured in the environment", null: true

    end
  end
end
