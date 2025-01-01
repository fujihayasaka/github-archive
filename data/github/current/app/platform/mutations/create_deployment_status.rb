# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class CreateDeploymentStatus < Platform::Mutations::Base
      description "Create a deployment status."

      minimum_accepted_scopes ["repo_deployment"]

      # Required arguments
      argument :deployment_id, ID, "The node ID of the deployment.", required: true, loads: Objects::Deployment
      argument :state, Enums::DeploymentStatusState, "The state of the deployment.", required: true

      # Non-required arguments
      argument :description, String, "A short description of the status. Maximum length of 140 characters.", required: false, default_value: ""
      argument :environment, String, "If provided, updates the environment of the deploy. Otherwise, does not modify the environment.", required: false
      argument :environment_url, String, "Sets the URL for accessing your environment.", required: false, default_value: ""
      argument :auto_inactive, Boolean, "Adds a new inactive status to all non-transient, non-production environment deployments with the same repository and environment name as the created status's deployment.", required: false, default_value: true
      argument :log_url, String, "The log URL to associate with this status. \
      This URL should contain output to keep the user updated while the task is running \
      or serve as historical information for what happened in the deployment.", required: false, default_value: ""

      error_fields

      field :deployment_status, Objects::DeploymentStatus, "The new deployment status.", null: true

      extras [:execution_errors]

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, deployment:, **inputs)
        repo = deployment.repository
        permission.async_owner_if_org(repo).then do |org|
          permission.access_allowed? :write_deployment_status,
            resource: repo,
            current_repo: repo,
            current_org: org,
            allow_integrations: true,
            allow_user_via_granular_actor: true
        end
      end

      def resolve(deployment:, execution_errors:, **inputs)
        repository = deployment.repository

        context[:permission].authorize_content(:deployment_status, :create, repository: repository)

        auto_inactive = inputs.delete(:auto_inactive)

        status = deployment.statuses.build(inputs.to_h)
        status.creator = context[:viewer]

        if context[:permission].integration_user_request?
          status.performed_via_integration = context[:integration]
        end

        if status.save
          if auto_inactive
            CreateAutoInactiveDeploymentStatuses.perform_later(deployment, true)
          end

          {
            deployment_status: status,
            errors: [],
          }
        else
          Platform::UserErrors.append_legacy_mutation_model_errors_to_context(status, execution_errors)

          errors = status.errors.map do |error|
            {
              message: "#{error.attribute} #{error.message}",
              short_message: "#{error.attribute} #{error.message}",
              attribute: error.attribute,
            }
          end

          {
            deployment_status: nil,
            errors: errors,
          }
        end
      end
    end
  end
end
