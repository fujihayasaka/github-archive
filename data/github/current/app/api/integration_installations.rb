# typed: true
# frozen_string_literal: true

class Api::IntegrationInstallations < Api::App
  include ReceiveSchemaWithOpenApi

  class InstallationError < StandardError; end

  USER_OR_USER_VIA_GITHUB_APP_ACCESS_ONLY = "You must authenticate with an access token authorized to a GitHub App, a personal access token, or basic auth in order to ".freeze
  USER_ACCESS_ONLY = "You must authenticate with a personal access token or basic auth in order to ".freeze

  get "/installation/repositories", operation_id: "apps/list-repos-accessible-to-installation" do
    set_forbidden_message \
      "You must authenticate with an installation access token in order to " +
      "list repositories for an installation."

    control_access :list_installation_repositories,
      resource: current_integration,
      installation: current_integration_installation,
      organization: fetch_organization(current_integration_installation),
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: false

    repository_ids = current_integration_installation.repository_ids(resource: "metadata").sort
    total_count = repository_ids.count

    repository_ids = paginate_rel(repository_ids)

    repositories = Repositories::Public.load_repositories(repository_ids)
    Repository.prefill_associations(repositories)

    show_blackbird_code_search_status = if current_integration.feature_flag_enabled?(:blackbird_list_repositories_with_index_status, default: false)
      Repository::SearchDependency.prefill_blackbird_code_search_status(repositories)
    end

    deliver :integration_installation_repositories_hash,
      { repositories: repositories, total_count: total_count,
        repository_selection: current_integration_installation.repository_selection },
      { show_blackbird_code_search_status: }
  end

  delete "/installation/token", operation_id: "apps/revoke-installation-access-token", resolve_tenant_context: :rtc_for_current_integration_installation, skip_rate_limit: true do
    set_forbidden_message "You must authenticate with an installation access token in order to revoke it"

    control_access :revoke_installation_token,
      resource: current_integration_installation,
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: false

    receive_with_schema("installation", "revoke-token")

    authentication_token = ServerToServerTokens.domain.by_unhashed_token(request_credentials.token)
    record_or_404(authentication_token)

    ServerToServerTokens.domain.destroy(T.must(authentication_token).id)

    deliver_empty(status: 204)
  end

  # List repositories for the authenticated user within an installation.
  get "/user/installations/:installation_id/repositories", operation_id: "apps/list-installation-repos-for-authenticated-user" do
    set_forbidden_message USER_OR_USER_VIA_GITHUB_APP_ACCESS_ONLY + "list repositories for an installation."

    @accepted_scopes = %w(user read:user)

    installation = find_installation!

    control_access :list_installation_repositories_for_user,
      resource: installation,
      organization: fetch_organization(installation),
      challenge: true,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    repositories =
      if current_user.feature_flag_enabled?(:sort_list_installation_repos_for_authenticated_user_by_id, default: false)
        repository_ids = current_user.associated_installation_repository_ids(installation).sort
        total_count = repository_ids.count

        repository_ids = paginate_rel(repository_ids)
        Repositories::Public.load_repositories(repository_ids)
      else
        repositories = Repository.where(id: current_user.associated_installation_repository_ids(installation))
        total_count = repositories.count

        paginate_rel(repositories.sorted_by(:full_name, "asc"))
      end

    Repository.prefill_associations(repositories)

    show_blackbird_code_search_status = if installation.integration.feature_flag_enabled?(:blackbird_list_repositories_with_index_status, default: false)
      Repository::SearchDependency.prefill_blackbird_code_search_status(repositories)
    end

    deliver :integration_installation_repositories_hash,
      { repositories: repositories, total_count: total_count },
      { show_blackbird_code_search_status: }
  end

  # Add a repository to an installation
  put "/user/installations/:installation_id/repositories/:repository_id", operation_id: "apps/add-repo-to-installation-for-authenticated-user" do
    @accepted_scopes = %w(repo)

    repo = find_repo!
    installation = find_installation!

    if can_access_repo_but_may_not_be_able_to_manage?(repo)
      forbidden_message = build_forbidden_action_on_repo_message(
        actor: current_user,
        repo: repo,
        installation: installation,
        action: :add_repositories,
      )
      set_forbidden_message forbidden_message
    end

    control_access :installation_repo_admin,
      installation: installation,
      resource: repository = repo,
      allow_integrations: false,
      allow_user_via_granular_actor: false

    if installation.repository_ids(repository_ids: [repository.id]).any?
      # Introducing strict validation of the installation-repository.add
      # JSON schema would cause breaking changes for integrators
      # skip_validation until a rollout strategy can be determined
      # see: https://github.com/github/ecosystem-api/issues/1555
      receive_with_schema("installation-repository", "add", skip_validation: true)
      return deliver_empty(status: 204)
    end

    result = IntegrationInstallation::RepositoryEditor.perform(installation, action: :add, repositories: [repository], editor: current_user, entry_point: :rest_api_add_repo_to_installation_for_authenticated_user)

    if result.success?
      # Introducing strict validation of the installation-repository.add
      # JSON schema would cause breaking changes for integrators
      # skip_validation until a rollout strategy can be determined
      # see: https://github.com/github/ecosystem-api/issues/1555
      receive_with_schema("installation-repository", "add", skip_validation: true)
      return deliver_empty(status: 204)
    end

    deliver_error!(422, message: result.error)
  end

  # Remove a repository from an installation
  delete "/user/installations/:installation_id/repositories/:repository_id", operation_id: "apps/remove-repo-from-installation-for-authenticated-user" do
    @accepted_scopes = %w(repo)

    repo = find_repo!
    installation = find_installation!

    if can_access_repo_but_may_not_be_able_to_manage?(repo)
      forbidden_message = build_forbidden_action_on_repo_message(
        actor: current_user,
        repo: repo,
        installation: installation,
        action: :remove_repositories,
      )
      set_forbidden_message forbidden_message
    end

    control_access :installation_repo_admin,
      installation: installation,
      resource: repository = repo,
      allow_integrations: false,
      allow_user_via_granular_actor: false

    if installation.installed_on_all_repositories?
      deliver_error!(422, message: "This installation is on all repositories, please update in the Web UI.")
    elsif installation.repository_ids(repository_ids: [repository.id]).none?
      # Introducing strict validation of the installation-repository.delete
      # JSON schema would cause breaking changes for integrators
      # skip_validation until a rollout strategy can be determined
      # see: https://github.com/github/ecosystem-api/issues/1555
      receive_with_schema("installation-repository", "delete", skip_validation: true)

      return deliver_empty(status: 204)
    elsif installation.repository_ids.count == 1
      deliver_error!(422, message: "Cannot remove the last repository from this installation.")
    end

    entry_point = Permissions::Service::EntryPoint.build(
      :rest_api_remove_repo_from_installation_for_authenticated_user,
      actor: installation,
      target: installation.target,
      actor_owner: installation.integration,
    )
    result = IntegrationInstallation::RepositoryEditor.perform(
      installation,
      action: :remove,
      repositories: [repository],
      editor: current_user,
      entry_point: entry_point,
    )

    if result.success?
      # Introducing strict validation of the installation-repository.delete
      # JSON schema would cause breaking changes for integrators
      # skip_validation until a rollout strategy can be determined
      # see: https://github.com/github/ecosystem-api/issues/1555
      receive_with_schema("installation-repository", "delete", skip_validation: true)
      return deliver_empty(status: 204)
    end

    deliver_error!(422, message: result.error)
  end

  # Internal: Resolve the tenant context for the current authenticated
  # installation.
  #
  # Returns a Business or nil.
  def rtc_for_current_integration_installation
    current_integration_installation&.resolve_tenant
  end

  private

  def build_forbidden_action_on_repo_message(actor:, repo:, installation:, action:)
    check = IntegrationInstallation::Permissions.check(
      installation: installation,
      actor: actor,
      action: action,
      repositories: [repo],
    )

    # Regardless of the check state, error_message is always buildable
    check.error_message
  end

  def find_installation!(installation_id = params[:installation_id])
    deliver_error!(404) unless logged_in?

    installation = IntegrationInstallation.user_installable.find_by(id: installation_id)
    record_or_404(installation)

    if current_user.can_access_installation?(installation)
      return installation
    end

    deliver_error!(404)
  end

  # See https://github.com/github/github/pull/108438 for context and follow ups
  def can_access_repo_but_may_not_be_able_to_manage?(repo)
    return true if repo.public?
    repo.pullable_by?(current_user) && scope?(current_user, "repo")
  end

  def fetch_organization(installation)
    return unless installation.present?
    installation.target.organization? ? installation.target : nil
  end
end
