module PackageToRepoMapping
  # A container for repository matches, so we don't have load the actual Repository object if e.g. it doesn't exist yet
  class RepoMatch
    attr_reader :github_repository_id, :nwo
    def self.from_repo(repo)
      new(repo.github_repository_id, repo.nwo)
    end

    def initialize(github_repository_id, nwo)
      @github_repository_id = github_repository_id
      @nwo = nwo
    end
  end
end
