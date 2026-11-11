# typed: true
# frozen_string_literal: true

class Api::Codespaces::Secrets::User < Api::Codespaces
  include Api::Codespaces::Secrets::Helpers

  # Get user public key for encrypting secrets
  get "/user/codespaces/secrets/public-key", operation_id: "codespaces/get-public-key-for-authenticated-user" do
    control_access :access_codespace_secrets,
      resource: current_user,
      challenge: true,
      forbid: true,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    deliver_error!(404) unless ::GitHub.codespaces_enabled?

    key_id, key = ::Secrets.github_public_key(
      owner: current_user,
      key_name: Platform::EncryptionKeys::CODESPACES_SECRETS
    )

    deliver_raw({ key_id: key_id.to_s, key: key })
  end

  # Get all of a user's Codespaces secrets
  # returns the secret's name, timestamps, visibility and their selected repository API urls
  get "/user/codespaces/secrets", operation_id: "codespaces/list-secrets-for-authenticated-user" do
    control_access :access_codespace_secrets,
      resource: current_user,
      challenge: true,
      forbid: true,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    deliver_error!(404) unless ::GitHub.codespaces_enabled?

    secrets = paginate_rel(
      Codespaces::UserSecret.for(current_user)
    )

    deliver(:codespaces_user_secrets_hash, {
      secrets: secrets,
      total_count: secrets.total_entries
    })
  end

  # Get a matching user's Codespaces secret
  # returns the secret's name, timestamps, visibility and their selected repository API urls
  get "/user/codespaces/secrets/:secret_name", operation_id: "codespaces/get-secret-for-authenticated-user" do
    control_access :access_codespace_secrets,
      resource: current_user,
      challenge: true,
      forbid: true,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    deliver_error!(404) unless ::GitHub.codespaces_enabled?

    secret = Codespaces::UserSecret.for_user_and_name(current_user, params[:secret_name])

    if secret.fetch_credential
      deliver(:codespaces_user_secret_hash, secret)
    else
      deliver_error!(404)
    end
  end

  # Store an updated user's Codespace's secret for a write user scope
  put "/user/codespaces/secrets/:secret_name", operation_id: "codespaces/create-or-update-secret-for-authenticated-user" do
    control_access :manage_codespaces_user_secret,
      resource: current_user,
      challenge: true,
      forbid: true,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    deliver_error!(404) unless ::GitHub.codespaces_enabled?

    data = receive_with_openapi

    validate_non_empty_secret_value!(data["encrypted_value"], owner: current_user)

    secret = Codespaces::UserSecret.new(
      name: params[:secret_name],
      user: current_user,
      key_id: data["key_id"],
      encrypted_value: data["encrypted_value"]
    )

    secret_exists = !!secret.fetch_credential

    # The API initially shipped with `selected_repository_ids` typed as an array of strings so we need to be backwards
    # compatible.
    if data["selected_repository_ids"]
      data["selected_repository_ids"] = data["selected_repository_ids"]
        .map { |id| Integer(id, exception: false) }
        .compact
    end
    secret_exists ? handle_update(secret, data) : handle_create(secret, data)
  end

  delete "/user/codespaces/secrets/:secret_name", operation_id: "codespaces/delete-secret-for-authenticated-user" do
    control_access :manage_codespaces_user_secret,
      resource: current_user,
      challenge: true,
      forbid: true,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    deliver_error!(404) unless ::GitHub.codespaces_enabled?

    secret = Codespaces::UserSecret.for_user_and_name(current_user, params[:secret_name])

    deliver_error!(404) if !secret.fetch_credential

    validate_secret_access!(secret)

    if !secret.delete
      deliver_error!(500, message: "Unable to delete the secret. Please try again later.")
    end

    deliver_empty status: 204
  end

  private

  def handle_create(secret, data)
    secret.repository_ids = filter_selected_repository_ids(data["selected_repository_ids"] || [])
    if secret.save
      deliver_empty status: 201
    else
      deliver_error!(
        422,
        message: "Failed to store secret",
        errors: secret.errors.full_messages,
        documentation_url: @documentation_url
      )
    end
  end

  def handle_update(secret, data)
    validate_secret_access!(secret)
    secret.repository_ids = filter_selected_repository_ids(data["selected_repository_ids"] || secret.repository_ids)
    if secret.update
      deliver_empty status: 204
    else
      deliver_error!(
        422,
        message: "Failed to update secret",
        errors: secret.errors.full_messages,
        documentation_url: @documentation_url
      )
    end
  end

  def validate_secret_access!(secret)
    return if secret.repository_ids.blank?

    allowed_secret_repository_ids = ProgrammaticActor::RepositoryFilter.perform(actor: current_user,
      repository_ids: secret.repository_ids,
      resource: "codespaces_secrets"
    )
    allowed_secret_repository_ids = cap_filter.authorized_resource_ids(
      Repository.where(id: allowed_secret_repository_ids)
    )
    allowed_secret_repository_ids = Codespaces::RepositoryQuery.visible_repo_ids(current_user, allowed_secret_repository_ids)
    # Bail if we had to filter _any_ of the secret's current repositories
    deliver_error!(404) if allowed_secret_repository_ids.count != secret.repository_ids.count
  end

  def filter_selected_repository_ids(selected_repository_ids)
    filtered_repository_ids = ProgrammaticActor::RepositoryFilter.perform(actor: current_user,
      repository_ids: selected_repository_ids,
      resource: "codespaces_secrets"
    )
    filtered_repository_ids = cap_filter.authorized_resource_ids(
      Repository.where(id: filtered_repository_ids)
    )
    filtered_repository_ids = Codespaces::RepositoryQuery.visible_repo_ids(current_user, filtered_repository_ids)
    # Bail if we had to filter _any_ of the selected repositories whether for FGP or for CAP
    deliver_error!(404) if filtered_repository_ids.count != selected_repository_ids.count
    filtered_repository_ids
  end
end
