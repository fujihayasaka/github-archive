# typed: true
# frozen_string_literal: true

class Api::DeploymentStatuses < Api::App
  include ReceiveSchemaWithOpenApi

  # Create a DeploymentStatus
  #
  # DeploymentsStatus are meant to be immutable.  If a Deployment has multiple
  # deployment statuses, the deployer should just create a new deployment status.
  #
  # To create a deployment status, you must have push rights to the repo. For
  # OAuth access, you must also have the appropriate scopes.
  post "/repositories/:repository_id/deployments/:deployment_id/statuses", operation_id: "repos/create-deployment-status" do
    control_access :write_deployment_status,
      resource: deployment = find_repo_deployment!,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    GitHub.dogstats.time("deployment_status.time", tags: ["action:create"]) do
      attrs = [
        :state,
        :description,
        :environment_url,
        :target_url,
        :log_url,
        :auto_inactive,
        :environment
      ]

      data = receive(Hash)
      data = attr(data, *attrs)

      # For compatibility we allow both `target_url` and `log_url` to be
      # passed in. But the DeploymentStatus model only accepts `log_url`.
      target_url = data.delete("target_url")
      data["log_url"] ||= target_url

      if data["auto_inactive"].nil?
        data["auto_inactive"] = true
      end

      auto_inactive = data.delete("auto_inactive")

      deployment_status = deployment.statuses.build(data)
      deployment_status.creator = current_user

      if integration_user_request?
        deployment_status.performed_via_integration = current_integration
      end

      if DeploymentStatus::STATES.exclude?(deployment_status.state)
        invalid_state = true
      end

      if !invalid_state && deployment_status.save
        GitHub.dogstats.increment("deployment_status", tags: ["action:create", "valid:true"])
        if auto_inactive
          CreateAutoInactiveDeploymentStatuses.perform_later(deployment, true)
        end

        # Introducing strict validation of the deployment-status.create
        # JSON schema would cause breaking changes for integrators.
        # skip_validation until a rollout strategy can be determined
        # see: https://github.com/github/ecosystem-api/issues/1555
        _ = receive_with_schema("deployment-status", "create", skip_validation: true)
        deliver :deployment_status_hash, deployment_status, status: 201
      else
        GitHub.dogstats.increment("deployment_status", tags: ["action:create", "valid:false"])
        error_message = if invalid_state
          # Copy the model validation error for the preview states so they
          # aren't exposed yet with a different error.
          [{
           resource: "DeploymentStatus",
           code: "custom",
           field: "state",
           message: "state is not included in the list",
         }]
        else
          deployment_status.errors
        end

        if error_message.respond_to?(:messages) &&
            error_message.messages[:log_url].present?

          log_url = error_message.delete(:log_url)
          error_message.add(:target_url, log_url.first)
        end

        deliver_error 422, errors: error_message
      end
    end
  end

  # Get statuses for a Deployment.
  get "/repositories/:repository_id/deployments/:deployment_id/statuses", operation_id: "repos/list-deployment-statuses" do
    control_access :read_deployment_status,
      resource: deployment = find_repo_deployment!,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    deployment_statuses = paginate_rel(deployment.statuses)
    GitHub::PrefillAssociations.prefill_associations(deployment_statuses, [:creator, { deployment: :repository }], available_records: [deployment.repository])

    deliver :deployment_status_hash, deployment_statuses
  end

  # Get a status for a Deployment.
  get "/repositories/:repository_id/deployments/:deployment_id/statuses/:status_id", operation_id: "repos/get-deployment-status" do

    control_access :read_deployment_status,
      resource: deployment = find_repo_deployment!,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    deployment_status = find_repo_deployment_status!
    GitHub::PrefillAssociations.prefill_associations(deployment_status, [:creator, { deployment: :repository }], available_records: [deployment.repository])

    deliver :deployment_status_hash, deployment_status
  end

  # Halts with a 404 if no Repository is found.
  # Returns a Repository instance, or nil.
  def find_repo_deployment!
    repo = find_repo!
    deployment = repo.deployments.where(id: params[:deployment_id]).first
    record_or_404(deployment)
  end

  def find_repo_deployment_status!
    deployment = find_repo_deployment!
    deployment_status = deployment.statuses.where(id: params[:status_id]).first
    record_or_404(deployment_status)
  end
end
