# typed: true
# frozen_string_literal: true

class GitHubModels::RepositoryAccessPoliciesController < AbstractRepositoryController
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency

  before_action :require_feature
  before_action :github_models_required
  before_action :ensure_admin_access
  before_action :parse_json_params, only: [:create, :destroy]

  # Allow making requests to this endpoint from React apps using the `verifiedFetch` function:
  allow_verified_fetch only: [:create, :destroy]

  layout "repository_settings"

  def self.react_bundle_name
    "github-models-repo-settings"
  end

  depends_on_clusters ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    only: [:show]

  depends_on_clusters ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    ApplicationRecord::Iam,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    only: [:show],
    optional: true

  def show
    # For orgs, we need to check if the org has models enabled
    org_models_enabled = if organization_access_policy
      T.must(organization_access_policy).models_enabled_for_org?
    elsif current_repository.owner&.user?
      user = T.cast(current_repository.owner, ::User)
      ## For user owned repositories, if the user is an enterprise managed user
      # and the enterprise managed business does not have models access enabled.
      # disable the ability to enable models in the UI
      if user.is_enterprise_managed?
        user.enterprise_managed_business&.models_access_enabled?
      # Otherwise, we allow user-owned repositories to see repo level settings regardless of any organization policy.
      else
        true
      end
    else
      true
    end

    payload = T.let({
      ownerDisplayLogin: current_repository.owner.display_login,
      repositoryName: current_repository.name,
      isAccessConfigurable: org_models_enabled,
      repositoryOwnerType: current_repository.organization ? "organization" : "user",
      repositoryAccessPolicy: {
        isRepoModelsEnabled: repository_access_policy.models_enabled_for_repo?,
      }
    }, GitHubModels::Types::RepositoryAccessPolicyShowPayload)

    render_react_app(
      payload: payload,
      title: "#{current_repository.name} settings · GitHub Models access policy",
      page_data: {
        selected_link: :github_models_repo_settings,
        stafftools: stafftools_user_path(current_repository),
      },
    )
  end

  def create
    success = models_access_repo_config.enable_models_access(current_user, force: true)
    status = success ? :ok : :unprocessable_entity
    render status: status, json: repository_access_policy.to_h
  end

  def destroy
    success = models_access_repo_config.disable_models_access(current_user, force: true)
    status = success ? :ok : :unprocessable_entity
    render status: status, json: repository_access_policy.to_h
  end

  private

  sig { returns T.nilable(GitHubModels::OrganizationAccessPolicy) }
  memoize def organization_access_policy
    repo_owner = current_repository.owner
    GitHubModels::OrganizationAccessPolicy.new(org: repo_owner) if repo_owner&.organization?
  end

  sig { returns GitHubModels::RepositoryAccessPolicy }
  memoize def repository_access_policy
    GitHubModels::RepositoryAccessPolicy.new(repo: current_repository)
  end

  sig { returns GitHubModels::ModelsAccessRepoConfig }
  def models_access_repo_config
    GitHubModels::ModelsAccessRepoConfig.new(current_repository)
  end

  sig { void }
  def require_feature
    render_404 unless GitHubModels::Repository.new(repository: current_repository).models_available_for_repo?
  end
end
