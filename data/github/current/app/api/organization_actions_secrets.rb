# typed: true
# frozen_string_literal: true

require "github/kredz_client"

class Api::OrganizationActionsSecrets < Api::App
  include Api::App::CryptoKeyHelper
  include Api::App::CredzSecretsHelper
  include Api::App::SecretsHelpers
  include GitHub::KredzClient
  include ReceiveSchemaWithOpenApi

  # For Local development, you need bin/server running and github/kredz running (credz service)

  # Get public key for encrypting secrets
  get "/organizations/:organization_id/actions/secrets/public-key", operation_id: "actions/get-org-public-key" do
    deliver_error! 404 unless org_secrets_enabled?

    org = find_org!
    deliver_error! 404 unless can_use_org_secrets?(org)

    control_access :read_actions_secrets_org,
      resource: org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_ACTIONS_SECRETS_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    public_key = if GitHub.enterprise?
      { key_identifier: "1", key: GitHub.actions_secrets_public_key }
    else
      generate_diet_earthsmoke_key_payload(name: Platform::EncryptionKeys::CUSTOM_TASKS, scope: org.next_global_id)
    end

    payload = { key_id: public_key[:key_identifier], key: public_key[:key] }

    deliver_raw(payload)
  end

  # Get the name and timestamps of all secrets set for the organization
  get "/organizations/:organization_id/actions/secrets", operation_id: "actions/list-org-secrets" do
    deliver_error! 404 unless org_secrets_enabled?

    org = find_org!
    deliver_error! 404 unless can_use_org_secrets?(org)

    control_access :read_actions_secrets_org,
      resource: org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_ACTIONS_SECRETS_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    result = rescue_from_secrets_errors do
      Secrets.list(
        app: GitHub.launch_github_app,
        owner: org,
        actor: current_user,
      )
    end

    validate_listing!(result)

    # We map to an Array so pagination works
    secrets = paginate_rel(result.credentials.map { |cred| cred })

    deliver :actions_org_secrets_hash, { secrets: secrets, org: org, total_count: secrets.total_entries }
  end

  # Get a single secret
  get "/organizations/:organization_id/actions/secrets/:name", operation_id: "actions/get-org-secret" do
    deliver_error! 404 unless org_secrets_enabled?

    org = find_org!
    deliver_error! 404 unless can_use_org_secrets?(org)

    control_access :read_actions_secrets_org,
      resource: org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_ACTIONS_SECRETS_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    result = rescue_from_secrets_errors do
      Secrets.fetch(
        name: params[:name],
        app: GitHub.launch_github_app,
        owner: org,
        actor: current_user,
      )
    end

    deliver_error! 404 unless result

    deliver :actions_org_secret_hash, { secret: result.credential, org: org }
  end

  # Delete a secret
  delete "/organizations/:organization_id/actions/secrets/:name", operation_id: "actions/delete-org-secret" do
    deliver_error! 404 unless org_secrets_enabled?

    org = find_org!
    deliver_error! 404 unless can_use_org_secrets?(org)

    control_access :write_actions_secrets_org,
      resource: org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_ACTIONS_SECRETS_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    receive_with_schema("organization-actions-secret", "delete-org-secret")

    result = rescue_from_secrets_errors do
      Secrets.delete(
        name: params[:name],
        app: GitHub.launch_github_app,
        owner: org,
        actor: current_user,
      )
    end

    deliver_error! 404 unless result

    deliver_empty status: (result.success ? 204 : 404)
  end

  # Store a secret for an organization for a write user.
  put "/organizations/:organization_id/actions/secrets/:name", operation_id: "actions/create-or-update-org-secret" do
    deliver_error! 404 unless org_secrets_enabled?

    org = find_org!
    deliver_error! 404 unless can_use_org_secrets?(org)

    control_access :write_actions_secrets_org,
      resource: org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_ACTIONS_SECRETS_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    data = receive_with_schema("organization-actions-secret", "set-org-secret")
    value = data["encrypted_value"]
    key_identifier = data["key_id"]
    visibility = GitHub::KredzClient::Credz::FROM_VISIBILITY_MAP[data["visibility"]]
    selected_repository_ids = data["selected_repository_ids"]

    validation = Credz.validate_org_secret(params[:name], value, visibility)
    unless validation.succeeded?
      deliver_error! 422, message: validation.error, documentation_url: @documentation_url
    end

    value = if GitHub.enterprise?
      decrypt_enterprise_value(value)
    else
      pack_earthsmoke_value(Platform::EncryptionKeys::CUSTOM_TASKS, key_identifier, value)
    end

    encoded_value = Base64.strict_encode64(value)

    # Filter repositories to org repositories
    org_repository_ids = org.repositories.where(id: selected_repository_ids).map(&:global_relay_id)

    # result is a GitHub::Launch::Services::Credz::StoreResponse
    result = rescue_from_secrets_errors do
      Secrets.store(
        name: params[:name],
        app: GitHub.launch_github_app, # we always store secrets in the prod launch env (even lab)
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

  # Get the repositories for a secret with `selected` visibility
  get "/organizations/:organization_id/actions/secrets/:name/repositories", operation_id: "actions/list-selected-repos-for-org-secret" do
    deliver_error! 404 unless org_secrets_enabled?

    org = find_org!
    deliver_error! 404 unless can_use_org_secrets?(org)


    control_access :read_actions_secrets_org,
      resource: org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_ACTIONS_SECRETS_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    # Fetch secret from credz
    result = rescue_from_secrets_errors do
      Secrets.fetch(
        name: params[:name],
        app: GitHub.launch_github_app,
        owner: org,
        actor: current_user,
      )
    end

    deliver_error! 404 unless result

    total_count = result.credential.selected_repositories_count

    repository_ids = map_selected_repo_global_ids(result.credential)
    repositories = org.repositories.where(id: repository_ids)
    repositories = paginate_rel(repositories.sorted_by(:full_name, "asc"))

    deliver :actions_secret_repositories_hash, { repositories: repositories, total_count: total_count }
  end

  # Add a repository for a secret with `selected` visibility
  put "/organizations/:organization_id/actions/secrets/:name/repositories/:repository_id", operation_id: "actions/add-selected-repo-to-org-secret" do
    deliver_error! 404 unless org_secrets_enabled?

    org = find_org!
    deliver_error! 404 unless can_use_org_secrets?(org)

    control_access :write_actions_secrets_org,
      resource: org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_ACTIONS_SECRETS_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    receive_with_schema("organization-actions-secret", "set-org-secret-repository")

    # Fetch secret from credz
    result = rescue_from_secrets_errors do
      Secrets.fetch(
        name: params[:name],
        app: GitHub.launch_github_app,
        owner: org,
        actor: current_user,
      )
    end

    deliver_error! 404 unless result

    credential = result.credential
    unless credential.visibility == :VISIBILITY_SELECTED_REPOSITORIES
      deliver_error! 409, errors: "You cannot update selected repositories for a secret when the visibility is not set to 'selected'"
    end

    # Validate repository
    repo = find_repo!
    deliver_error! 422 unless repo.organization_id == org.id

    selected_repository_node_ids = credential.selected_repositories.map(&:global_id).to_set
    selected_repositories_ids = selected_repository_node_ids.map { |global_id| Platform::Helpers::NodeIdentification.from_global_id(global_id)[1] }
    selected_repositories = org.repositories.where(id: selected_repositories_ids)

    selected_repository_global_ids = selected_repositories.map(&:global_relay_id).to_set
    selected_repository_global_ids << repo.global_relay_id

    # result is a GitHub::Launch::Services::Credz::StoreResponse
    result = rescue_from_secrets_errors do
      Secrets.update(
        name: credential.name,
        app: GitHub.launch_github_app, # we always store secrets in the prod launch env (even lab)
        owner: org,
        actor: current_user,
        visibility: credential.visibility,
        selected_repositories: selected_repository_global_ids.to_a
      )
    end

    validate_result!(result)
    deliver_empty(status: 204)
  end

  # Delete a repository for a secret with `selected` visibility
  delete "/organizations/:organization_id/actions/secrets/:name/repositories/:repository_id", operation_id: "actions/remove-selected-repo-from-org-secret" do
    deliver_error! 404 unless org_secrets_enabled?

    org = find_org!
    deliver_error! 404 unless can_use_org_secrets?(org)

    control_access :write_actions_secrets_org,
      resource: org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_ACTIONS_SECRETS_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    receive_with_schema("organization-actions-secret", "delete-org-secret-repository")

    result = rescue_from_secrets_errors do
      Secrets.fetch(
        name: params[:name],
        app: GitHub.launch_github_app,
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

    # Filter repositories to org repositories
    org_repository_ids = org.repositories.where(id: selected_repositories_ids).map(&:global_relay_id)

    # result is a GitHub::Launch::Services::Credz::StoreResponse
    result = rescue_from_secrets_errors do
      Secrets.update(
        name: credential.name,
        app: GitHub.launch_github_app, # we always store secrets in the prod launch env (even lab)
        owner: org,
        actor: current_user,
        visibility: credential.visibility,
        selected_repositories: org_repository_ids
      )
    end

    validate_result!(result)
    deliver_empty(status: 204)
  end

  # Replace the selected repositories for a secret with `selected` visibility
  put "/organizations/:organization_id/actions/secrets/:name/repositories", operation_id: "actions/set-selected-repos-for-org-secret" do
    deliver_error! 404 unless org_secrets_enabled?

    org = find_org!
    deliver_error! 404 unless can_use_org_secrets?(org)

    control_access :write_actions_secrets_org,
      resource: org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_ACTIONS_SECRETS_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    data = receive_with_schema("organization-actions-secret", "set-org-secret-repositories")

    result = rescue_from_secrets_errors do
      Secrets.fetch(
        name: params[:name],
        app: GitHub.launch_github_app,
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

    # Filter repositories to org repositories
    org_repository_ids = org.repositories.where(id: selected_repository_ids).map(&:global_relay_id)

    # result is a GitHub::Launch::Services::Credz::StoreResponse
    result = rescue_from_secrets_errors do
      Secrets.update(
        name: credential.name,
        app: GitHub.launch_github_app, # we always store secrets in the prod launch env (even lab)
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
    # Exclude legacy plans
    Billing::ActionsPermission.new(organization).status[:error][:reason] != "PLAN_INELIGIBLE"
  end

  def org_secrets_enabled?
    GitHub.actions_enabled?
  end
end
