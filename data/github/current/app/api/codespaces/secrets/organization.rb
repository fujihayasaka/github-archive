# typed: true
# frozen_string_literal: true

require "github/kredz_client"

class Api::Codespaces::Secrets::Organization < Api::Codespaces
  include Api::App::CredzSecretsHelper
  include Api::App::CryptoKeyHelper
  include Api::App::SecretsHelpers
  include GitHub::KredzClient
  include Api::Codespaces::Secrets::Helpers

  get "/organizations/:organization_id/codespaces/secrets/public-key", operation_id: "codespaces/get-org-public-key" do
    org = find_org!
    deliver_error! 404 unless org.codespaces_feature_enabled?

    control_access :read_org_codespaces_secrets,
      resource: org,
      forbid: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    secret_type = secret_type_param!(params[:secret_type], org)
    name = key_name_for_secret_type(secret_type)
    public_key = generate_diet_earthsmoke_key_payload(name:, scope: org.next_global_id)

    payload = { key_id: public_key[:key_identifier], key: public_key[:key] }

    deliver_raw(payload)
  end

  # Get the name and timestamps of all secrets set for the Organization
  get "/organizations/:organization_id/codespaces/secrets", operation_id: "codespaces/list-org-secrets" do
    org = find_org!
    deliver_error! 404 unless org.codespaces_feature_enabled?

    control_access :read_org_codespaces_secrets,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true

    secret_type = secret_type_param!(params[:secret_type], org)
    app = secrets_app_for_secret_type(secret_type)

    result = rescue_from_secrets_errors do
      ::Secrets.list(
        app:,
        owner: org,
        actor: current_user,
      )
    end

    validate_listing!(result)

    secrets = paginate_rel(result.credentials.to_a)

    deliver(:codespaces_org_secrets_hash, {
      secrets: secrets,
      total_count: secrets.total_entries,
      org: org
    })
  end

  # Get the name and timestamp of a secret in the Organization
  get "/organizations/:organization_id/codespaces/secrets/:name", operation_id: "codespaces/get-org-secret" do
    org = find_org!
    deliver_error! 404 unless org.codespaces_feature_enabled?

    control_access :read_org_codespaces_secrets,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true

    secret_type = secret_type_param!(params[:secret_type], org)
    app = secrets_app_for_secret_type(secret_type)

    result = rescue_from_secrets_errors do
      ::Secrets.fetch(
        name: params[:name],
        app:,
        owner: org,
        actor: current_user,
      )
    end

    validate_listing!(result)

    deliver :codespaces_org_secret_hash, result.credential
  end

  put "/organizations/:organization_id/codespaces/secrets/:name", operation_id: "codespaces/create-or-update-org-secret" do
    org = find_org!
    deliver_error! 404 unless org.codespaces_feature_enabled?

    control_access :write_org_codespaces_secrets,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true

    data = receive_with_openapi # validate the schema
    value = data["encrypted_value"]
    validate_non_empty_secret_value!(value, owner: org)

    key_identifier = data["key_id"]
    visibility = GitHub::KredzClient::Credz::FROM_VISIBILITY_MAP[data["visibility"]]

    secret_type = secret_type_param!(data["secret_type"], org)
    app = secrets_app_for_secret_type(secret_type)
    key_name = key_name_for_secret_type(secret_type)
    if secret_type == :host_setup && visibility != GitHub::KredzClient::Credz::CREDENTIAL_VISIBILITY_ALL_REPOS
      deliver_error! 422, message: "Host setup secrets must use 'all' repository visibility", documentation_url: @documentation_url
    end

    validation = Credz.validate_org_secret(params[:name], value, visibility)
    unless validation.succeeded?
      deliver_error! 422, message: validation.error, documentation_url: @documentation_url
    end

    value = pack_earthsmoke_value(key_name, key_identifier, value)

    encoded_value = Base64.strict_encode64(value)

    selected_repository_ids = data["selected_repository_ids"] || []
    accessible_repo_ids = ProgrammaticActor::RepositoryFilter.perform(
      actor: current_user, repository_ids: selected_repository_ids, resource: "metadata",
    )
    # Filter repositories to org repositories
    org_repository_ids = org.repositories.where(id: accessible_repo_ids).map(&:global_relay_id)

    # result is a GitHub::Launch::Services::Credz::StoreResponse
    result = rescue_from_secrets_errors do
      ::Secrets.store(
        name: params[:name],
        app:,
        owner: org,
        actor: current_user,
        value: encoded_value,
        visibility: visibility,
        selected_repositories: org_repository_ids,
      )
    end

    validate_result!(result)
    validate_storage!(result)

    deliver_empty(status: result.updated ? 204 : 201)
  end

  delete "/organizations/:organization_id/codespaces/secrets/:name", operation_id: "codespaces/delete-org-secret" do
    org = find_org!
    deliver_error! 404 unless org.codespaces_feature_enabled?

    control_access :write_org_codespaces_secrets,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true

    receive_with_openapi # validate the schema

    secret_type = secret_type_param!(params[:secret_type], org)
    app = secrets_app_for_secret_type(secret_type)

    result = rescue_from_secrets_errors do
      ::Secrets.delete(
        name: params[:name],
        app:,
        owner: org,
        actor: current_user,
      )
    end

    deliver_error! 404 unless result

    deliver_empty status: (result.success ? 204 : 404)
  end

  get "/organizations/:organization_id/codespaces/secrets/:name/repositories", operation_id: "codespaces/list-selected-repos-for-org-secret" do
    org = find_org!
    deliver_error! 404 unless org.codespaces_feature_enabled?

    control_access :read_org_codespaces_secrets,
    resource: org,
    allow_integrations: true,
    allow_user_via_granular_actor: true,
    forbid: true

    # Fetch secret from credz
    result = rescue_from_secrets_errors do
      ::Secrets.fetch(
        name: params[:name],
        app: Apps::Privileged.integration(:codespaces_production),
        owner: org,
        actor: current_user,
      )
    end

    deliver_error! 404 unless result

    repository_ids = map_selected_repo_global_ids(result.credential)

    accessible_repo_ids = ProgrammaticActor::RepositoryFilter.perform(
      actor: current_user, repository_ids: repository_ids, resource: "metadata",
    )

    repositories = Repository.where(id: accessible_repo_ids).sorted_by(:full_name, "asc")
    repositories = paginate_rel(repositories.sorted_by(:full_name, "asc"))
    deliver :codespaces_secret_repositories_hash, { repositories: repositories, total_count: repositories.total_entries }
  end

  # Add a repository for a secret with `selected` visibility
  put "/organizations/:organization_id/codespaces/secrets/:name/repositories/:repository_id", operation_id: "codespaces/add-selected-repo-to-org-secret" do
    org = find_org!
    deliver_error! 404 unless org.codespaces_feature_enabled?

    control_access :write_org_codespaces_secrets,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true

    receive_with_openapi # validate the schema

    # Fetch secret from credz
    result = rescue_from_secrets_errors do
      ::Secrets.fetch(
        name: params[:name],
        app: Apps::Privileged.integration(:codespaces_production),
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

    control_access :get_repo,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    deliver_error! 422 unless repo.organization_id == org.id

    selected_repository_node_ids = credential.selected_repositories.map(&:global_id).to_set
    selected_repositories_ids = selected_repository_node_ids.map { |global_id| Platform::Helpers::NodeIdentification.from_global_id(global_id)[1] }
    selected_repositories = org.repositories.where(id: selected_repositories_ids).order(:id)

    selected_repository_global_ids = selected_repositories.map(&:global_relay_id).to_set
    selected_repository_global_ids << repo.global_relay_id

    # result is a GitHub::Launch::Services::Credz::StoreResponse
    result = rescue_from_secrets_errors do
      ::Secrets.update(
        name: credential.name,
        app: Apps::Privileged.integration(:codespaces_production), # we always store secrets in the prod launch env (even lab)
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
  delete "/organizations/:organization_id/codespaces/secrets/:name/repositories/:repository_id", operation_id: "codespaces/remove-selected-repo-from-org-secret" do
    org = find_org!
    deliver_error! 404 unless org.codespaces_feature_enabled?

    control_access :write_org_codespaces_secrets,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true

    receive_with_openapi # validate the schema

    result = rescue_from_secrets_errors do
      ::Secrets.fetch(
        name: params[:name],
        app: Apps::Privileged.integration(:codespaces_production),
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

    control_access :get_repo,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    deliver_error! 422 unless repo.organization_id == org.id

    repo_id = params[:repository_id]

    selected_repositories_ids = map_selected_repo_global_ids(credential).to_set
    deliver_error! 404 unless selected_repositories_ids.include?(repo_id)

    selected_repositories_ids.delete(repo_id)

    # Filter repositories to org repositories
    org_repository_ids = org.repositories.where(id: selected_repositories_ids).order(:id).map(&:global_relay_id)

    # result is a GitHub::Launch::Services::Credz::StoreResponse
    result = rescue_from_secrets_errors do
      ::Secrets.update(
        name: credential.name,
        app: Apps::Privileged.integration(:codespaces_production), # we always store secrets in the prod launch env (even lab)
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
  put "/organizations/:organization_id/codespaces/secrets/:name/repositories", operation_id: "codespaces/set-selected-repos-for-org-secret" do
    org = find_org!
    deliver_error! 404 unless org.codespaces_feature_enabled?

    control_access :write_org_codespaces_secrets,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true

    data = receive_with_openapi # validate the schema

    result = rescue_from_secrets_errors do
      ::Secrets.fetch(
        name: params[:name],
        app: Apps::Privileged.integration(:codespaces_production),
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

    accessible_repo_ids = ProgrammaticActor::RepositoryFilter.perform(
      actor: current_user, repository_ids: selected_repository_ids, resource: "metadata",
    )

    # Filter repositories to org repositories
    org_repository_ids = org.repositories.where(id: accessible_repo_ids).order(:id).map(&:global_relay_id)

    # result is a GitHub::Launch::Services::Credz::StoreResponse
    result = rescue_from_secrets_errors do
      ::Secrets.update(
        name: credential.name,
        app: Apps::Privileged.integration(:codespaces_production), # we always store secrets in the prod launch env (even lab)
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
