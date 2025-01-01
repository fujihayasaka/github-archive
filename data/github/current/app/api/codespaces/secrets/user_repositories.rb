# typed: true
# frozen_string_literal: true

class Api::Codespaces::Secrets::UserRepositories < Api::Codespaces
  # Get the repositories where a user's Codespaces secret will be available.
  # Returns an object with "total_count" and a "repositories" list of repository objects.
  get "/user/codespaces/secrets/:secret_name/repositories", operation_id: "codespaces/list-repositories-for-secret-for-authenticated-user" do
    control_access :access_codespace_secrets,
      resource: current_user,
      challenge: true,
      forbid: true,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    deliver_error!(404) unless ::GitHub.codespaces_enabled?

    secret = find_secret!

    repo_ids = ProgrammaticActor::RepositoryFilter.perform(actor: current_user, repository_ids: secret.repository_ids, resource: "codespaces_secrets")
    repos = Repository.where(id: Codespaces::RepositoryQuery.visible_repo_ids(current_user, repo_ids))
    repos = cap_filter.authorized_resources(repos)
    deliver :codespaces_user_secret_repositories_hash, { repositories: repos, total_count: repos.count }
  end

  # Set the repositories where a user's Codespaces secret will be available, specified by :selected_repository_ids.
  # Returns nothing with status 204 if successful.
  put "/user/codespaces/secrets/:secret_name/repositories", operation_id: "codespaces/set-repositories-for-secret-for-authenticated-user" do
    control_access :manage_codespaces_user_secret,
      resource: current_user,
      challenge: true,
      forbid: true,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    data = receive_with_openapi

    deliver_error!(404) unless ::GitHub.codespaces_enabled?

    secret = find_secret!
    validate_secret_access!(secret)

    filtered_repository_ids = ProgrammaticActor::RepositoryFilter.perform(actor: current_user,
      repository_ids: data["selected_repository_ids"],
      resource: "codespaces_secrets"
    )
    filtered_repository_ids = cap_filter.authorized_resources(Repository.where(id: filtered_repository_ids)).map(&:id)
    filtered_repository_ids = Codespaces::RepositoryQuery.visible_repo_ids(current_user, filtered_repository_ids)
    deliver_error!(404) if data["selected_repository_ids"].count != filtered_repository_ids.count

    update_secret_repositories!(secret, filtered_repository_ids)
  end

  # Adds a specified repository to a Codespaces secret.
  # Returns nothing with status 204 if successful.
  put "/user/codespaces/secrets/:secret_name/repositories/:repository_id", operation_id: "codespaces/add-repository-for-secret-for-authenticated-user" do
    repo = find_repo! # Doing this ahead of `control_access` gives us CAP filtering.
    control_access :manage_codespaces_user_secret,
      resource: current_user,
      challenge: true,
      allow_integrations: false,
      allow_user_via_granular_actor: true
    deliver_error!(404) unless ::GitHub.codespaces_enabled?

    secret = find_secret!
    validate_secret_access!(secret)

    filtered_repository_ids = Codespaces::RepositoryQuery.visible_repo_ids(current_user, [repo.id])

    deliver_error!(404) if filtered_repository_ids.blank?

    update_secret_repositories!(secret, secret.repository_ids + filtered_repository_ids)
  end

  # Removes a specified repository from a Codespaces secret.
  # Returns nothing with status 204 if successful.
  delete "/user/codespaces/secrets/:secret_name/repositories/:repository_id", operation_id: "codespaces/remove-repository-for-secret-for-authenticated-user" do
    repo = find_repo! # Doing this ahead of `control_access` gives us CAP filtering.
    control_access :manage_codespaces_user_secret,
      resource: current_user,
      challenge: true,
      allow_integrations: false,
      allow_user_via_granular_actor: true
    deliver_error!(404) unless ::GitHub.codespaces_enabled?

    secret = find_secret!

    validate_secret_access!(secret)

    update_secret_repositories!(secret, secret.repository_ids - [repo.id])
  end

  private

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

  def find_secret!
    secret = Codespaces::UserSecret.for_user_and_name(current_user, params[:secret_name])
    deliver_error!(404) unless secret.fetch_credential
    secret
  end

  def update_secret_repositories!(secret, repository_ids)
    secret.repository_ids = repository_ids
    if secret.update
      deliver_empty(status: 204)
    else
      deliver_error!(
        422,
        message: "Failed to store secret",
        errors: secret.errors.full_messages,
        documentation_url: @documentation_url
      )
    end
  end
end
