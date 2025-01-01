# typed: true
# frozen_string_literal: true

class GitHubModels::RepositoryAccessPolicy
  include GitHub::Memoizer

  sig { params(repo: Repository).void }
  def initialize(repo:)
    @repo = repo
  end

  sig { returns GitHubModels::Types::RepositoryAccessPolicy }
  def to_h
    {
      isRepoModelsEnabled: !!(GitHub.models_enabled? && models_enabled_for_repo?),
    }
  end

  # Are models enabled for this repository?
  sig { returns T::Boolean }
  memoize def models_enabled_for_repo?
    GitHubModels::ModelsAccessRepoConfig::new(@repo).models_access_enabled?
  end
end
