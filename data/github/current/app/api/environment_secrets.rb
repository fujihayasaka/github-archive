# typed: false
# frozen_string_literal: true

require "github/kredz_client"


class Api::EnvironmentSecrets < Api::App
  include Api::App::CryptoKeyHelper
  include Api::App::CredzSecretsHelper
  include Api::App::SecretsHelpers
  include GitHub::KredzClient
  include ReceiveSchemaWithOpenApi

  # For local development, you need bin/server running and github/launch running
  # (credz service)

  # Get public key for encrypting secrets
  get "/repositories/:repository_id/environments/:environment/secrets/public-key", operation_id: "actions/get-environment-public-key" do
    @route_owner = "@github/c2c-actions-experience"
    @documentation_url = "/rest/reference/actions#get-an-environment-public-key"

    repo = find_repo!
    deliver_error! 404 unless can_use_env_secrets_api?(repo)

    environment = Environment.find_by(repository: repo, name: params[:environment])

    deliver_error! 404 unless environment

    control_access :read_environment_secrets,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    public_key = if GitHub.enterprise?
      { key_identifier: "1", key: GitHub.actions_secrets_public_key }
    else
      generate_diet_earthsmoke_key_payload(name: Platform::EncryptionKeys::CUSTOM_TASKS, scope: environment.next_global_id)
    end

    payload = { key_id: public_key[:key_identifier], key: public_key[:key] }

    deliver_raw(payload)
  end

  get "/repositories/:repository_id/environments/:environment/secrets", operation_id: "actions/list-environment-secrets" do
    @route_owner = "@github/c2c-actions-experience"
    @documentation_url = "/rest/reference/actions#list-environment-secrets"

    repo = find_repo!
    deliver_error! 404 unless can_use_env_secrets_api?(repo)

    environment = Environment.find_by(repository: repo, name: params[:environment])

    deliver_error! 404 unless environment

    control_access :read_environment_secrets,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    result = rescue_from_secrets_errors do
      Secrets.list(
        app: GitHub.launch_github_app,
        owner: environment,
        actor: current_user,
      )
    end

    validate_listing!(result)

    secrets = paginate_rel(result.credentials.map { |cred| cred })

    deliver :actions_secrets_hash, { secrets: secrets, total_count: secrets.total_entries }
  end

  # Get a single secret
  get "/repositories/:repository_id/environments/:environment/secrets/:name", operation_id: "actions/get-environment-secret" do
    @route_owner = "@github/c2c-actions-experience"
    @documentation_url = "/rest/reference/actions#get-an-environment-secret"

    repo = find_repo!
    deliver_error! 404 unless can_use_env_secrets_api?(repo)

    environment = Environment.find_by(repository: repo, name: params[:environment])
    deliver_error! 404 unless environment


    control_access :read_environment_secrets,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    result = rescue_from_secrets_errors do
      Secrets.fetch(
        name: params[:name],
        app: GitHub.launch_github_app,
        owner: environment,
        actor: current_user,
      )
    end

    deliver_error! 404 unless result

    deliver :actions_secret_hash, result.credential
  end

  # Delete a secret
  delete "/repositories/:repository_id/environments/:environment/secrets/:name", operation_id: "actions/delete-environment-secret" do
    @route_owner = "@github/c2c-actions-experience"
    @documentation_url = "/rest/reference/actions#delete-an-environment-secret"

    repo = find_repo!
    deliver_error! 404 unless can_use_env_secrets_api?(repo)

    environment = Environment.find_by(repository: repo, name: params[:environment])
    deliver_error! 404 unless environment

    control_access :write_environment_secrets,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    receive_with_schema("environment-actions-secret", "delete-environment-secret")

    result = rescue_from_secrets_errors do
      Secrets.delete(
        name: params[:name],
        app: GitHub.launch_github_app,
        owner: environment,
        actor: current_user,
      )
    end

    deliver_error! 404 unless result

    deliver_empty status: (result.success ? 204 : 404)
  end

  put "/repositories/:repository_id/environments/:environment/secrets/:name", operation_id: "actions/create-or-update-environment-secret" do
    @route_owner = "@github/c2c-actions-experience"
    @documentation_url = "/rest/reference/actions#create-or-update-an-environment-secret"

    repo = find_repo!
    deliver_error! 404 unless can_use_env_secrets_api?(repo)

    environment = Environment.find_by(repository: repo, name: params[:environment])
    deliver_error! 404 unless environment

    control_access :write_environment_secrets,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    data = receive_with_schema("environment-actions-secret", "set-environment-secret")
    value = data["encrypted_value"]
    key_identifier = data["key_id"]

    validation = Credz.validate_secret(params[:name], value)
    unless validation.succeeded?
      deliver_error! 422, message: validation.error, documentation_url: @documentation_url
    end

    value = if GitHub.enterprise?
      decrypt_enterprise_value(value)
    else
      pack_earthsmoke_value(Platform::EncryptionKeys::CUSTOM_TASKS, key_identifier, value)
    end

    encoded_value = Base64.strict_encode64(value)

    # result is a GitHub::Launch::Services::Credz::StoreResponse
    result = rescue_from_secrets_errors do
      Secrets.store(
        name: params[:name],
        app: GitHub.launch_github_app,
        owner: environment,
        actor: current_user,
        value: encoded_value,
      )
    end

    validate_result!(result)
    validate_storage!(result)

    status = 201
    if result.updated
      status = 204
    end

    deliver_empty(status: status)
  end

  private

  # Only let users with the feature flag enabled access this API
  def can_use_env_secrets_api?(repository)
    repository.can_use_environments?
  end
end
