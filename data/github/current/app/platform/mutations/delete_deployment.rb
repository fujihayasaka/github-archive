# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class DeleteDeployment < Platform::Mutations::Base
      description "Deletes a deployment."

      minimum_accepted_scopes ["repo_deployment"]

      argument :id, ID, "The Node ID of the deployment to be deleted.", required: true, loads: Objects::Deployment, as: :deployment

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, deployment:, **inputs)
        repository = deployment.repository
        permission.async_owner_if_org(repository).then do |org|
          repository.resources.deployments.writable_by?(permission.viewer) &&
          permission.access_allowed?(
            :write_deployment,
            resource: repository,
            current_repo: repository,
            current_org: org,
            allow_integrations: true,
            allow_user_via_granular_actor: true,
          )
        end
      end

      def resolve(deployment:, **inputs)
        repository = deployment.repository

        context[:permission].authorize_content(:deployment, :delete, deployment: deployment, repo: deployment.repository)

        deployments_count = repository.deployments.where(environment: deployment.environment).count
        if deployment.active? && deployments_count > 1
          raise Errors::Unprocessable.new("We cannot delete an active deployment unless it is the only deployment in a given environment.")
        else
          deployment.destroy!
          {}
        end
      end
    end
  end
end
