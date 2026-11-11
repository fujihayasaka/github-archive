# typed: true
# frozen_string_literal: true

require "diet_earthsmoke"
require "github/kredz_client"

class Api::AgentSecrets < Api::App
  include Api::App::CryptoKeyHelper
  include Api::App::CredzSecretsHelper
  include Api::App::SecretsHelpers
  include GitHub::KredzClient
  include ReceiveSchemaWithOpenApi

  def self.agent_secrets_app
    Apps::Privileged.integration(:agent_secrets)
  end

  get "/repositories/:repository_id/agents/secrets/public-key", operation_id: "agents/get-repo-public-key" do
    repo = find_repo!
    deliver_error! 404 unless agents_enabled?(repo)

    control_access :read_agent_secrets_repo,
      resource: repo,
      forbid: repo.public?,
      forbid_message: "Agent secrets are not available for public repositories",
      allow_integrations: true,
      enforce_oauth_app_policy: true, allow_user_via_granular_actor: true

    public_key = generate_diet_earthsmoke_key_payload(name: Platform::EncryptionKeys::AGENT_SECRETS, scope: repo.next_global_id)

    payload = { key_id: public_key[:key_identifier], key: public_key[:key] }

    deliver_raw(payload)
  end

  get "/repositories/:repository_id/agents/secrets", operation_id: "agents/list-repo-secrets" do
    repo = find_repo!
    deliver_error! 404 unless agents_enabled?(repo)

    control_access :read_agent_secrets_repo,
      resource: repo,
      forbid: repo.public?,
      forbid_message: "Agent secrets are not available for public repositories",
      allow_integrations: true,
      enforce_oauth_app_policy: true, allow_user_via_granular_actor: true

    result = rescue_from_secrets_errors do
      Secrets.list(
        app: self.class.agent_secrets_app,
        owner: repo,
        actor: current_user,
      )
    end

    validate_listing!(result)

    secrets = paginate_rel(result.credentials.map { |cred| cred })

    deliver :agent_secrets_hash, { secrets: secrets, total_count: secrets.total_entries }
  end

  get "/repositories/:repository_id/agents/organization-secrets", operation_id: "agents/list-repo-organization-secrets" do
    repo = find_repo!
    deliver_error! 404 unless agents_enabled?(repo)

    control_access :read_agent_secrets_repo,
      resource: repo,
      forbid: repo.public?,
      forbid_message: "Agent secrets are not available for public repositories",
      allow_integrations: true, allow_user_via_granular_actor: true

    deliver_error! 422 unless repo.organization_id

    result = rescue_from_secrets_errors do
      Secrets.list_repository(app: self.class.agent_secrets_app, repository: repo, environments: [], actor: current_user)
    end

    validate_listing!(result)

    secrets = paginate_rel(result.organization_secrets.map { |cred| cred })

    deliver :agent_secrets_hash, { secrets: secrets, total_count: secrets.total_entries }
  end

  get "/repositories/:repository_id/agents/secrets/:name", operation_id: "agents/get-repo-secret" do
    repo = find_repo!
    deliver_error! 404 unless agents_enabled?(repo)

    control_access :read_agent_secrets_repo,
      resource: repo,
      forbid: repo.public?,
      forbid_message: "Agent secrets are not available for public repositories",
      allow_integrations: true,
      enforce_oauth_app_policy: true, allow_user_via_granular_actor: true

    result = rescue_from_secrets_errors do
      Secrets.fetch(
        name: params[:name],
        app: self.class.agent_secrets_app,
        owner: repo,
        actor: current_user,
      )
    end

    deliver_error! 404 unless result

    deliver :agent_secret_hash, result.credential
  end

  delete "/repositories/:repository_id/agents/secrets/:name", operation_id: "agents/delete-repo-secret", read_from_replicas: true do
    repo = find_repo!
    deliver_error! 404 unless agents_enabled?(repo)

    control_access :write_agent_secrets_repo,
      resource: repo,
      forbid: repo.public?,
      forbid_message: "Agent secrets are not available for public repositories",
      allow_integrations: true,
      enforce_oauth_app_policy: true, allow_user_via_granular_actor: true

    receive_with_openapi

    result = rescue_from_secrets_errors do
      Secrets.delete(
        name: params[:name],
        app: self.class.agent_secrets_app,
        owner: repo,
        actor: current_user,
      )
    end

    deliver_error! 404 unless result

    deliver_empty status: (result.success ? 204 : 404)
  end

  put "/repositories/:repository_id/agents/secrets/:name", operation_id: "agents/create-or-update-repo-secret", read_from_replicas: true do
    repo = find_repo!
    deliver_error! 404 unless agents_enabled?(repo)

    control_access :write_agent_secrets_repo,
      resource: repo,
      forbid: repo.public?,
      forbid_message: "Agent secrets are not available for public repositories",
      allow_integrations: true,
      enforce_oauth_app_policy: true, allow_user_via_granular_actor: true

    data = receive_with_openapi
    value = data["encrypted_value"]
    key_identifier = data["key_id"]

    validation = Credz.validate_secret(params[:name], value)
    unless validation.succeeded?
      deliver_error! 422, message: validation.error, documentation_url: @documentation_url
    end

    value = pack_earthsmoke_value(Platform::EncryptionKeys::AGENT_SECRETS, key_identifier, value)

    encoded_value = Base64.strict_encode64(value)

    result = rescue_from_secrets_errors do
      Secrets.store(
        name: params[:name],
        app: self.class.agent_secrets_app,
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

  private

  def agents_enabled?(repo)
    Secrets::AppsHelper.agents_enabled?(repo: repo, owner: repo.owner)
  end
end
