# typed: false
# frozen_string_literal: true

module Api::Serializer::DeploymentStatusesDependency
  # Creates a Hash to be serialized to JSON.
  #
  # deployment_status - DeploymentStatus instance.
  # options    - Hash
  #
  # Returns a Hash if the DeploymentStatus exists, or nil.
  def deployment_status_hash(deployment_status, options = {})
    return nil unless deployment_status

    repository_url = "/repos/#{deployment_status.repository.name_with_owner_for_api(use: options[:serialize_login])}"
    deployment_url = "#{repository_url}/deployments/#{deployment_status.deployment.id}"
    status_url     = "#{deployment_url}/statuses/#{deployment_status.id}"

    hash = {
      url: url(status_url),
      id: deployment_status.id,
      node_id: global_id_for(deployment_status, options),
      state: deployment_status.state,
      creator: user_hash(deployment_status.creator, content_options(options)),
      description: deployment_status.description.to_s,
      environment: deployment_status.environment,
      target_url: deployment_status.log_url.to_s,
      created_at: time(deployment_status.created_at),
      updated_at: time(deployment_status.updated_at),
      deployment_url: url(deployment_url),
      repository_url: url(repository_url),
      environment_url: deployment_status.environment_url.to_s,
      log_url: deployment_status.log_url.to_s
    }

    options = Api::SerializerOptions.from(options)
    hash[:performed_via_github_app] = integration_hash(deployment_status.performed_via_integration, options)

    hash
  end
end
