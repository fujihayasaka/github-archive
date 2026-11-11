# typed: true
# frozen_string_literal: true

require "github/kredz_client"

class Api::DependabotSecrets < Api::App
  include Api::App::CryptoKeyHelper
  include Api::App::CredzSecretsHelper
  include Api::App::SecretsHelpers
  include GitHub::KredzClient
  include ReceiveSchemaWithOpenApi

  # For Local development, you need bin/server running and github/kredz running (credz service)

  # Get public key for encrypting secrets
  get "/repositories/:repository_id/dependabot/secrets/public-key", operation_id: "dependabot/get-repo-public-key" do
    repo = find_repo!

    control_access :read_dependabot_secrets,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    public_key = if GitHub.enterprise?
      { key_identifier: "1", key: GitHub.actions_secrets_public_key }
    else
      generate_diet_earthsmoke_key_payload(name: Platform::EncryptionKeys::DEPENDABOT_SECRETS, scope: repo.next_global_id)
    end

    payload = { key_id: public_key[:key_identifier], key: public_key[:key] }

    deliver_raw(payload)
  end

  # Get the name and timestamps of all secrets set for the Repository
  get "/repositories/:repository_id/dependabot/secrets", operation_id: "dependabot/list-repo-secrets" do
    repo = find_repo!

    control_access :read_dependabot_secrets,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    result = rescue_from_secrets_errors do
      Secrets.list(
        app: GitHub.dependabot_github_app,
        owner: repo,
        actor: current_user,
      )
    end

    validate_listing!(result)

    # We map to an Array so pagination works
    secrets = paginate_rel(result.credentials.map { |cred| cred })

    deliver :dependabot_secrets_hash, { secrets: secrets, total_count: secrets.total_entries }
  end

  # Get a single secret
  get "/repositories/:repository_id/dependabot/secrets/:name", operation_id: "dependabot/get-repo-secret" do
    repo = find_repo!

    control_access :read_dependabot_secrets,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    result = rescue_from_secrets_errors do
      Secrets.fetch(
        name: params[:name],
        app: GitHub.dependabot_github_app,
        owner: repo,
        actor: current_user,
      )
    end

    deliver_error! 404 unless result

    deliver :dependabot_secret_hash, result.credential
  end

  # Delete a secret
  delete "/repositories/:repository_id/dependabot/secrets/:name", operation_id: "dependabot/delete-repo-secret" do
    repo = find_repo!

    control_access :write_dependabot_secrets,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    receive_with_openapi

    result = rescue_from_secrets_errors do
      Secrets.delete(
        name: params[:name],
        app: GitHub.dependabot_github_app,
        owner: repo,
        actor: current_user,
      )
    end

    deliver_error! 404 unless result

    deliver_empty status: (result.success ? 204 : 404)
  end

  # Store a secret for the given App on repository for a write user.
  put "/repositories/:repository_id/dependabot/secrets/:name", operation_id: "dependabot/create-or-update-repo-secret" do
    repo = find_repo!

    control_access :write_dependabot_secrets,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    data = receive_with_openapi
    value = data["encrypted_value"]
    key_identifier = data["key_id"]

    validation = Credz.validate_secret(params[:name], value)
    unless validation.succeeded?
      deliver_error! 422, message: validation.error, documentation_url: @documentation_url
    end

    value = if GitHub.enterprise?
      decrypt_enterprise_value(value)
    else
      pack_earthsmoke_value(Platform::EncryptionKeys::DEPENDABOT_SECRETS, key_identifier, value)
    end

    encoded_value = Base64.strict_encode64(value)

    # result is a GitHub::Launch::Services::Credz::StoreResponse
    result = rescue_from_secrets_errors do
      Secrets.store(
        name: params[:name],
        app: GitHub.dependabot_github_app,
        owner: repo,
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
end
