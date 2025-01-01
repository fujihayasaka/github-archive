module PackageToRepoMapping
  class StrongMatcher < Matcher
    self.certainty = Certainty::MATCHING_MANIFEST

    def self.find_repo(package)
      possible_repo_id = package.releases
                           .published
                           .where("repository_id is NOT NULL")
                           .order("id desc")
                           .limit(1)
                           .pluck(:repository_id)
      return if possible_repo_id.empty?

      repo =
        Repository.public_repos.joins(:manifests)
          .where(github_repository_id: possible_repo_id)
          .merge(Manifest.where(
                   package_manager: package.package_manager,
                   name: package.label || package.name,
                 ))
          .where("CAST(#{Manifest.table_name}.name AS BINARY) = ?", package.label || package.name)
          .limit(1).first

      return RepoMatch.from_repo(repo) if repo.present?
    end
  end
end
