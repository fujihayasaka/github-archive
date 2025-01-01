# typed: true
# frozen_string_literal: true

class GitHubModels::Repository
  include GitHub::Memoizer

  sig { params(repository: ::Repository).void }
  def initialize(repository:)
    @repository = repository
  end

  # Public: Is models access available for this repository? (the user can turn it on in repo settings)
  sig { returns T::Boolean }
  memoize def models_available_for_repo?
    return false unless GitHub.models_enabled?


    # During previews, we do not want to show the models tab for public repositories
    if @repository.public? && !@repository.feature_enabled_for_repo_or_owner?(:github_models_repo_tab_on_public_repos)
      return false
    end

    # This feature force models to available regardless of the org settings below
    return true if @repository.feature_enabled_for_repo_or_owner?(:github_models_repo_integration)

    org = self.org
    if org
      # For org-owned repositories, we need to check if the org has models enabled
      GitHubModels::OrganizationAccessPolicy.new(org: org).models_available_for_org?
    else
      # For user-owned repositories, we check whether they should see the model repo settings
      @repository.feature_enabled_for_repo_or_owner?(:github_models_repo_access_policies)
    end
  end

  # TODO: This needs to be changed to hide the models tab if the organization has disabled models.
  # Public: Is models access enabled for this repository?
  sig { returns T::Boolean }
  memoize def models_enabled_for_repo?
    return false unless GitHub.models_enabled?

    # During previews, we do not want to show the models tab for public repositories
    if @repository.public? && !@repository.feature_enabled_for_repo_or_owner?(:github_models_repo_tab_on_public_repos)
      return false
    end

    # This feature force models to available regardless of the org settings below
    return true if @repository.feature_enabled_for_repo_or_owner?(:github_models_repo_integration)

    org = self.org
    if org
      return false unless GitHubModels::OrganizationAccessPolicy.new(org: org).models_enabled_for_org?
    else
      # For user-owned repositories, check whether they should've been able to enable models in the first place
      return false unless @repository.feature_enabled_for_repo_or_owner?(:github_models_repo_access_policies)
    end

    GitHubModels::RepositoryAccessPolicy.new(repo: @repository).models_enabled_for_repo?
  end

  # Public: Get the frontend payload representation of models the user has access to.
  sig { params(user: T.any(::User, GitHubModels::User)).returns(T::Array[GitHubModels::Types::RepoModel]) }
  def models(user:)
    unless @repository.feature_enabled_for_repo_or_owner?(:github_models_org_access_policies) && org
      models_user = user.is_a?(GitHubModels::User) ? user : GitHubModels::User.new(user: user)
      return models_user.models(sort: :publisher).map(&:to_repository_model)
    end

    org = self.org
    return [] unless org
    GitHubModels::OrganizationAccessPolicy.new(org: org).allowed_default_models.map(&:to_repository_model)
  end

  private

  sig { returns T.nilable(Organization) }
  memoize def org
    repo_owner = @repository.owner
    repo_owner.is_a?(Organization) ? repo_owner : nil
  end
end
