# typed: true
# frozen_string_literal: true

require "github/kredz_client"

class Api::OrganizationDependabotSecrets < Api::App
  include Api::App::CryptoKeyHelper
  include Api::App::CredzSecretsHelper
  include Api::App::SecretsHelpers
  include GitHub::KredzClient
  include ReceiveSchemaWithOpenApi

  # For Local development, you need bin/server running and github/kredz running (credz service)

  # Get public key for encrypting secrets
  get "/organizations/:organization_id/dependabot/secrets/public-key", operation_id: "dependabot/get-org-public-key" do
    org = find_org!

    control_access :read_org_dependabot_secrets,
      resource: org,
      forbid: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    public_key = if GitHub.enterprise?
      { key_identifier: "1", key: GitHub.actions_secrets_public_key }
    else
      generate_diet_earthsmoke_key_payload(name: Platform::EncryptionKeys::DEPENDABOT_SECRETS, scope: org.next_global_id)
    end

    payload = { key_id: public_key[:key_identifier], key: public_key[:key] }

    deliver_raw(payload)
  end

  # Get the name and timestamps of all dependabot secrets set for the organization
  get "/organizations/:organization_id/dependabot/secrets", operation_id: "dependabot/list-org-secrets" do
    org = find_org!

    control_access :read_org_dependabot_secrets,
      resource: org,
      forbid: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    result = rescue_from_secrets_errors do
      Secrets.list(
        app: GitHub.dependabot_github_app,
        owner: org,
        actor: current_user,
      )
    end

    validate_listing!(result)

    # We map to an Array so pagination works
    secrets = paginate_rel(result.credentials.map { |cred| cred })

    deliver :dependabot_org_secrets_hash, { secrets: secrets, org: org, total_count: secrets.total_entries }
  end

  # Get a single dependabot secret
  get "/organizations/:organization_id/dependabot/secrets/:name", operation_id: "dependabot/get-org-secret" do
    org = find_org!

    control_access :read_org_dependabot_secrets,
      resource: org,
      forbid: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    result = rescue_from_secrets_errors do
      Secrets.fetch(
        name: params[:name],
        app: GitHub.dependabot_github_app,
        owner: org,
        actor: current_user,
      )
    end

    deliver_error! 404 unless result

    deliver :dependabot_org_secret_hash, { secret: result.credential, org: org }
  end

  # Delete a dependabot secret
  delete "/organizations/:organization_id/dependabot/secrets/:name", operation_id: "dependabot/delete-org-secret" do
    org = find_org!

    control_access :write_org_dependabot_secrets,
      resource: org,
      forbid: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    receive_with_openapi

    result = rescue_from_secrets_errors do
      Secrets.delete(
        name: params[:name],
        app: GitHub.dependabot_github_app,
        owner: org,
        actor: current_user,
      )
    end

    deliver_error! 404 unless result

    deliver_empty status: (result.success ? 204 : 404)
  end

  # Store a dependabot secret for an organization for a write user.
  put "/organizations/:organization_id/dependabot/secrets/:name", operation_id: "dependabot/create-or-update-org-secret" do
    org = find_org!

    control_access :write_org_dependabot_secrets,
      resource: org,
      forbid: true,
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

    value = if GitHub.enterprise?
      decrypt_enterprise_value(value)
    else
      pack_earthsmoke_value(Platform::EncryptionKeys::DEPENDABOT_SECRETS, key_identifier, value)
    end

    encoded_value = Base64.strict_encode64(value)

    # Filter repositories to org repositories
    org_repository_ids = org.repositories.where(id: selected_repository_ids).map(&:global_relay_id)

    # result is a GitHub::Launch::Services::Credz::StoreResponse
    result = rescue_from_secrets_errors do
      Secrets.store(
        name: params[:name],
        app: GitHub.dependabot_github_app, # we always store secrets in the prod launch env (even lab)
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

  # Get the repositories for a dependabot secret with `selected` visibility
  get "/organizations/:organization_id/dependabot/secrets/:name/repositories", operation_id: "dependabot/list-selected-repos-for-org-secret" do
    org = find_org!

    control_access :read_org_dependabot_secrets,
      resource: org,
      forbid: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    # Fetch secret from credz
    result = rescue_from_secrets_errors do
      Secrets.fetch(
        name: params[:name],
        app: GitHub.dependabot_github_app,
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

  # Add a repository for a dependabot secret with `selected` visibility
  put "/organizations/:organization_id/dependabot/secrets/:name/repositories/:repository_id", operation_id: "dependabot/add-selected-repo-to-org-secret" do
    org = find_org!

    control_access :write_org_dependabot_secrets,
      resource: org,
      forbid: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    receive_with_openapi

    # Fetch secret from credz
    result = rescue_from_secrets_errors do
      Secrets.fetch(
        name: params[:name],
        app: GitHub.dependabot_github_app,
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
        app: GitHub.dependabot_github_app, # we always store secrets in the prod launch env (even lab)
        owner: org,
        actor: current_user,
        visibility: credential.visibility,
        selected_repositories: selected_repository_global_ids.to_a
      )
    end

    validate_result!(result)
    deliver_empty(status: 204)
  end

  # Delete a repository for a dependabot secret with `selected` visibility
  delete "/organizations/:organization_id/dependabot/secrets/:name/repositories/:repository_id", operation_id: "dependabot/remove-selected-repo-from-org-secret" do
    org = find_org!

    control_access :write_org_dependabot_secrets,
      resource: org,
      forbid: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    receive_with_openapi

    result = rescue_from_secrets_errors do
      Secrets.fetch(
        name: params[:name],
        app: GitHub.dependabot_github_app,
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
        app: GitHub.dependabot_github_app, # we always store secrets in the prod launch env (even lab)
        owner: org,
        actor: current_user,
        visibility: credential.visibility,
        selected_repositories: org_repository_ids
      )
    end

    validate_result!(result)
    deliver_empty(status: 204)
  end

  # Replace the selected repositories for a dependabot secret with `selected` visibility
  put "/organizations/:organization_id/dependabot/secrets/:name/repositories", operation_id: "dependabot/set-selected-repos-for-org-secret" do
    org = find_org!

    control_access :write_org_dependabot_secrets,
      resource: org,
      forbid: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    data = receive_with_openapi

    result = rescue_from_secrets_errors do
      Secrets.fetch(
        name: params[:name],
        app: GitHub.dependabot_github_app,
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
        app: GitHub.dependabot_github_app, # we always store secrets in the prod launch env (even lab)
        owner: org,
        actor: current_user,
        visibility: credential.visibility,
        selected_repositories: org_repository_ids
      )
    end

    validate_result!(result)
    deliver_empty(status: 204)
  end
end
