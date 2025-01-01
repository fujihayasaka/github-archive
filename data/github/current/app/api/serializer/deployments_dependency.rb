# typed: false
# frozen_string_literal: true

module Api::Serializer::DeploymentsDependency
  # Creates a Hash to be serialized to JSON.
  #
  # deployment - Deployment instance.
  # options    - Hash
  #
  # Returns a Hash if the Deployment exists, or nil.
  def deployment_hash(deployment, options = {})
    return nil unless deployment

    hash = simple_deployment_hash(deployment, options)

    hash[:creator] = user_hash(deployment.creator, content_options(options))
    hash[:sha] = deployment.sha
    hash[:ref] = deployment.ref
    hash[:payload] = deployment.json_payload
    hash[:transient_environment] = deployment.transient_environment?
    hash[:production_environment] = deployment.production_environment?

    options = Api::SerializerOptions.from(options)

    hash[:performed_via_github_app] = integration_hash(deployment.performed_via_integration, options)
    hash
  end

  def simple_deployment_hash(deployment, options = {})
    return nil unless deployment

    repository_url = "/repos/#{deployment.repository.name_with_owner_for_api(use: options[:serialize_login])}"
    deployment_url = "#{repository_url}/deployments/#{deployment.id}"

    hash = {
      url: url(deployment_url),
      id: deployment.id,
      node_id: global_id_for(deployment, options),
      task: deployment.task,
      original_environment: deployment.environment,
      environment: deployment.latest_environment,
      description: deployment.description,
      created_at: time(deployment.created_at),
      updated_at: time(deployment.updated_at),
      statuses_url: url("#{deployment_url}/statuses"),
      repository_url: url(repository_url),
    }
    hash
  end
end
