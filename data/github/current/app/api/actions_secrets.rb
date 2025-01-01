# typed: true
# frozen_string_literal: true

require "diet_earthsmoke"
require "github/kredz_client"

class Api::ActionsSecrets < Api::App
  include Api::App::CryptoKeyHelper
  include Api::App::CredzSecretsHelper
  include Api::App::SecretsHelpers
  include GitHub::KredzClient
  include ReceiveSchemaWithOpenApi

  # For Local development, you need bin/server running and github/kredz running (credz service)

  # Get public key for encrypting secrets
  get "/repositories/:repository_id/actions/secrets/public-key", operation_id: "actions/get-repo-public-key" do
    repo = find_repo!

    control_access :read_actions_secrets_repo,
      resource: repo,
      forbid: repo.public?,
      forbid_message: ActionsCiCdErrors::REPO_ACTIONS_SECRETS_READ_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    public_key = if GitHub.enterprise?
      { key_identifier: "1", key: GitHub.actions_secrets_public_key }
    else
      generate_diet_earthsmoke_key_payload(name: Platform::EncryptionKeys::CUSTOM_TASKS, scope: repo.next_global_id)
    end

    payload = { key_id: public_key[:key_identifier], key: public_key[:key] }

    deliver_raw(payload)
  end

  # Get the name and timestamps of all secrets set for the Repository
  get "/repositories/:repository_id/actions/secrets", operation_id: "actions/list-repo-secrets" do
    repo = find_repo!

    control_access :read_actions_secrets_repo,
      resource: repo,
      forbid: repo.public?,
      forbid_message: ActionsCiCdErrors::REPO_ACTIONS_SECRETS_READ_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    result = rescue_from_secrets_errors do
      Secrets.list(
        app: GitHub.launch_github_app,
        owner: repo,
        actor: current_user,
      )
    end

    validate_listing!(result)

    # We map to an Array so pagination works
    secrets = paginate_rel(result.credentials.map { |cred| cred })

    deliver :actions_secrets_hash, { secrets: secrets, total_count: secrets.total_entries }
  end

  # Get the name and timestamps of all organization secrets shared with the Repository
  get "/repositories/:repository_id/actions/organization-secrets", operation_id: "actions/list-repo-organization-secrets" do
    repo = find_repo!

    control_access :read_actions_secrets_repo,
      resource: repo,
      forbid: repo.public?,
      forbid_message: ActionsCiCdErrors::REPO_ACTIONS_SECRETS_READ_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    deliver_error! 422 unless repo.organization_id

    result = rescue_from_secrets_errors do
      Secrets.list_repository(app: GitHub.launch_github_app, repository: repo, environments: [], actor: current_user)
    end

    validate_listing!(result)

    # We map to an Array so pagination works
    secrets = paginate_rel(result.organization_secrets.map { |cred| cred })

    deliver :actions_secrets_hash, { secrets: secrets, total_count: secrets.total_entries }
  end

  # Get a single secret
  get "/repositories/:repository_id/actions/secrets/:name", operation_id: "actions/get-repo-secret" do
    repo = find_repo!

    control_access :read_actions_secrets_repo,
      resource: repo,
      forbid: repo.public?,
      forbid_message: ActionsCiCdErrors::REPO_ACTIONS_SECRETS_READ_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    result = rescue_from_secrets_errors do
      Secrets.fetch(
        name: params[:name],
        app: GitHub.launch_github_app,
        owner: repo,
        actor: current_user,
      )
    end

    deliver_error! 404 unless result

    deliver :actions_secret_hash, result.credential
  end

  # Delete a secret
  delete "/repositories/:repository_id/actions/secrets/:name", operation_id: "actions/delete-repo-secret" do
    repo = find_repo!

    control_access :write_actions_secrets_repo,
      resource: repo,
      forbid: repo.public?,
      forbid_message: ActionsCiCdErrors::REPO_ACTIONS_SECRETS_WRITE_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    receive_with_schema("actions-secret", "delete-secret")

    result = rescue_from_secrets_errors do
      Secrets.delete(
        name: params[:name],
        app: GitHub.launch_github_app,
        owner: repo,
        actor: current_user,
      )
    end

    deliver_error! 404 unless result

    deliver_empty status: (result.success ? 204 : 404)
  end

  # Store a secret for the given App on repository for a write user.
  put "/repositories/:repository_id/actions/secrets/:name", operation_id: "actions/create-or-update-repo-secret" do
    repo = find_repo!

    control_access :write_actions_secrets_repo,
      resource: repo,
      forbid: repo.public?,
      forbid_message: ActionsCiCdErrors::REPO_ACTIONS_SECRETS_WRITE_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    data = receive_with_schema("actions-secret", "set-secret")
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
