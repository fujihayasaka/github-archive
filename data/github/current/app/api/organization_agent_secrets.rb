# typed: true
# frozen_string_literal: true

require "diet_earthsmoke"
require "github/kredz_client"

class Api::OrganizationAgentSecrets < Api::App
  include Api::App::CryptoKeyHelper
  include Api::App::CredzSecretsHelper
  include Api::App::SecretsHelpers
  include GitHub::KredzClient
  include ReceiveSchemaWithOpenApi

  def self.agent_secrets_app
    Apps::Privileged.integration(:agent_secrets)
  end

  get "/organizations/:organization_id/agents/secrets/public-key", operation_id: "agents/get-org-public-key" do
    org = find_org!
    deliver_error! 404 unless agents_enabled?(org)
    deliver_error! 404 unless can_use_org_secrets?(org)

    control_access :read_agent_secrets_org,
      resource: org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_AGENT_SECRETS_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    public_key = generate_diet_earthsmoke_key_payload(name: Platform::EncryptionKeys::AGENT_SECRETS, scope: org.next_global_id)

    payload = { key_id: public_key[:key_identifier], key: public_key[:key] }

    deliver_raw(payload)
  end

  get "/organizations/:organization_id/agents/secrets", operation_id: "agents/list-org-secrets" do
    org = find_org!
    deliver_error! 404 unless agents_enabled?(org)
    deliver_error! 404 unless can_use_org_secrets?(org)

    control_access :read_agent_secrets_org,
      resource: org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_AGENT_SECRETS_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    result = rescue_from_secrets_errors do
      Secrets.list(
        app: self.class.agent_secrets_app,
        owner: org,
        actor: current_user,
      )
    end

    validate_listing!(result)

    secrets = paginate_rel(result.credentials.map { |cred| cred })

    deliver :agent_org_secrets_hash, { secrets: secrets, org: org, total_count: secrets.total_entries }
  end

  get "/organizations/:organization_id/agents/secrets/:name", operation_id: "agents/get-org-secret" do
    org = find_org!
    deliver_error! 404 unless agents_enabled?(org)
    deliver_error! 404 unless can_use_org_secrets?(org)

    control_access :read_agent_secrets_org,
      resource: org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_AGENT_SECRETS_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    result = rescue_from_secrets_errors do
      Secrets.fetch(
        name: params[:name],
        app: self.class.agent_secrets_app,
        owner: org,
        actor: current_user,
      )
    end

    deliver_error! 404 unless result

    deliver :agent_org_secret_hash, { secret: result.credential, org: org }
  end

  delete "/organizations/:organization_id/agents/secrets/:name", operation_id: "agents/delete-org-secret", read_from_replicas: true do
    org = find_org!
    deliver_error! 404 unless agents_enabled?(org)
    deliver_error! 404 unless can_use_org_secrets?(org)

    control_access :write_agent_secrets_org,
      resource: org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_AGENT_SECRETS_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    receive_with_openapi

    result = rescue_from_secrets_errors do
      Secrets.delete(
        name: params[:name],
        app: self.class.agent_secrets_app,
        owner: org,
        actor: current_user,
      )
    end

    deliver_error! 404 unless result

    deliver_empty status: (result.success ? 204 : 404)
  end

  put "/organizations/:organization_id/agents/secrets/:name", operation_id: "agents/create-or-update-org-secret", read_from_replicas: true do
    org = find_org!
    deliver_error! 404 unless agents_enabled?(org)
    deliver_error! 404 unless can_use_org_secrets?(org)

    control_access :write_agent_secrets_org,
      resource: org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_AGENT_SECRETS_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    data = receive_with_openapi
    value = data["encrypted_value"]
    key_identifier = data["key_id"]
    visibility = GitHub::KredzClient::Credz::FROM_VISIBILITY_MAP[data["visibility"]]
    selected_repository_ids = data["selected_repository_ids"]

    validation = Credz.validate_org_secret(params[:name], value, visibility)
    unless validation.succeeded?
      deliver_error! 422, message: validation.error, documentation_url: @documentation_url
    end

    value = pack_earthsmoke_value(Platform::EncryptionKeys::AGENT_SECRETS, key_identifier, value)

    encoded_value = Base64.strict_encode64(value)

    org_repository_ids = org.repositories.where(id: selected_repository_ids).map(&:global_relay_id)

    result = rescue_from_secrets_errors do
      Secrets.store(
        name: params[:name],
        app: self.class.agent_secrets_app,
        owner: org,
        actor: current_user,
        value: encoded_value,
        visibility: visibility,
        selected_repositories: org_repository_ids,
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

  get "/organizations/:organization_id/agents/secrets/:name/repositories", operation_id: "agents/list-selected-repos-for-org-secret" do
    org = find_org!
    deliver_error! 404 unless agents_enabled?(org)
    deliver_error! 404 unless can_use_org_secrets?(org)

    control_access :read_agent_secrets_org,
      resource: org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_AGENT_SECRETS_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    result = rescue_from_secrets_errors do
      Secrets.fetch(
        name: params[:name],
        app: self.class.agent_secrets_app,
        owner: org,
        actor: current_user,
      )
    end

    deliver_error! 404 unless result

    total_count = result.credential.selected_repositories_count

    repository_ids = map_selected_repo_global_ids(result.credential)
    repositories = org.repositories.where(id: repository_ids)
    repositories = paginate_rel(repositories.sorted_by(:full_name, "asc"))

    deliver :agent_secret_repositories_hash, { repositories: repositories, total_count: total_count }
  end

  put "/organizations/:organization_id/agents/secrets/:name/repositories/:repository_id", operation_id: "agents/add-selected-repo-to-org-secret", read_from_replicas: true do
    org = find_org!
    deliver_error! 404 unless agents_enabled?(org)
    deliver_error! 404 unless can_use_org_secrets?(org)

    control_access :write_agent_secrets_org,
      resource: org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_AGENT_SECRETS_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    receive_with_openapi

    result = rescue_from_secrets_errors do
      Secrets.fetch(
        name: params[:name],
        app: self.class.agent_secrets_app,
        owner: org,
        actor: current_user,
      )
    end

    deliver_error! 404 unless result

    credential = result.credential
    unless credential.visibility == :VISIBILITY_SELECTED_REPOSITORIES
      deliver_error! 409, errors: "You cannot update selected repositories for a secret when the visibility is not set to 'selected'"
    end

    repo = find_repo!
    deliver_error! 422 unless repo.organization_id == org.id

    selected_repository_node_ids = credential.selected_repositories.map(&:global_id).to_set
    selected_repositories_ids = selected_repository_node_ids.map { |global_id| Platform::Helpers::NodeIdentification.from_global_id(global_id)[1] }
    selected_repositories = org.repositories.where(id: selected_repositories_ids)

    selected_repository_global_ids = selected_repositories.map(&:global_relay_id).to_set
    selected_repository_global_ids << repo.global_relay_id

    result = rescue_from_secrets_errors do
      Secrets.update(
        name: credential.name,
        app: self.class.agent_secrets_app,
        owner: org,
        actor: current_user,
        visibility: credential.visibility,
        selected_repositories: selected_repository_global_ids.to_a
      )
    end

    validate_result!(result)
    deliver_empty(status: 204)
  end

  delete "/organizations/:organization_id/agents/secrets/:name/repositories/:repository_id", operation_id: "agents/remove-selected-repo-from-org-secret", read_from_replicas: true do
    org = find_org!
    deliver_error! 404 unless agents_enabled?(org)
    deliver_error! 404 unless can_use_org_secrets?(org)

    control_access :write_agent_secrets_org,
      resource: org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_AGENT_SECRETS_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    receive_with_openapi

    result = rescue_from_secrets_errors do
      Secrets.fetch(
        name: params[:name],
        app: self.class.agent_secrets_app,
        owner: org,
        actor: current_user,
      )
    end

    deliver_error! 404 unless result

    credential = result.credential
    unless credential.visibility == :VISIBILITY_SELECTED_REPOSITORIES
      deliver_error! 409, errors: "You cannot update selected repositories for a secret when the visibility is not set to 'selected'"
    end

    repo_id = params[:repository_id]
    selected_repositories_ids = map_selected_repo_global_ids(credential).to_set
    deliver_error! 404 unless selected_repositories_ids.include?(repo_id)

    selected_repositories_ids.delete(repo_id)

    org_repository_ids = org.repositories.where(id: selected_repositories_ids).map(&:global_relay_id)

    result = rescue_from_secrets_errors do
      Secrets.update(
        name: credential.name,
        app: self.class.agent_secrets_app,
        owner: org,
        actor: current_user,
        visibility: credential.visibility,
        selected_repositories: org_repository_ids
      )
    end

    validate_result!(result)
    deliver_empty(status: 204)
  end

  put "/organizations/:organization_id/agents/secrets/:name/repositories", operation_id: "agents/set-selected-repos-for-org-secret", read_from_replicas: true do
    org = find_org!
    deliver_error! 404 unless agents_enabled?(org)
    deliver_error! 404 unless can_use_org_secrets?(org)

    control_access :write_agent_secrets_org,
      resource: org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_AGENT_SECRETS_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    data = receive_with_openapi

    result = rescue_from_secrets_errors do
      Secrets.fetch(
        name: params[:name],
        app: self.class.agent_secrets_app,
        owner: org,
        actor: current_user,
      )
    end

    deliver_error! 404 unless result

    credential = result.credential
    unless credential.visibility == :VISIBILITY_SELECTED_REPOSITORIES
      deliver_error! 409, errors: "You cannot update selected repositories for a secret when the visibility is not set to 'selected'"
    end

    selected_repository_ids = data["selected_repository_ids"]

    org_repository_ids = org.repositories.where(id: selected_repository_ids).map(&:global_relay_id)

    result = rescue_from_secrets_errors do
      Secrets.update(
        name: credential.name,
        app: self.class.agent_secrets_app,
        owner: org,
        actor: current_user,
        visibility: credential.visibility,
        selected_repositories: org_repository_ids
      )
    end

    validate_result!(result)
    deliver_empty(status: 204)
  end

  private

  def can_use_org_secrets?(organization)
    Billing::ActionsPermission.new(organization).status[:error][:reason] != "PLAN_INELIGIBLE"
  end

  def agents_enabled?(org)
    Secrets::AppsHelper.agents_enabled?(repo: nil, owner: org)
  end
end
