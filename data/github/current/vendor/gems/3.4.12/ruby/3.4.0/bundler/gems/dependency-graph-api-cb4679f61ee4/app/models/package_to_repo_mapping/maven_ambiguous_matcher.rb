module PackageToRepoMapping
  class MavenAmbiguousMatcher < Matcher
    self.certainty = Certainty::MAVEN_INFERRED_NAMESPACE_MULTIPLE_MATCHES
    self.package_managers = [Types::PackageManager[:maven]]

    BATCH_SIZE = 100 # number of repos to check per query
    MAX_REPOS = 1000 # maximum number of repos we want to be searching through

    def self.find_repo(package)
      # Find all the repos that have a manifest with the same name as our package, sorted by star count and github_repository_id
      candidate_repo_ids = Manifest.left_joins(repository: :star_count_assoc)
                             .where(package_manager: package.package_manager,
                                    name: package.name)
                             .where("#{Repository.table_name}.public = true")
                             .order("#{StarCount.table_name}.star_count desc, #{Repository.table_name}.github_repository_id asc")
                             .distinct.limit(MAX_REPOS).pluck("repository_id")

      candidate_repo_ids.each_slice(BATCH_SIZE) do |repo_ids|
        # We need to find repositories where the manifest at root has the same groupId as the package we're mapping
        # we need the ORDER BY FIELD so our results are in the same order as repo_ids
        # that is by star_count and github_repository_id
        repo = Manifest.at_root
                 .where("name LIKE ?", "#{package.name.split(':', 2).first}%")
                 .where(repository_id: repo_ids)
                 .order(Arel.sql("FIELD(repository_id, #{repo_ids.join(', ')})"))
                 .first&.repository

        return RepoMatch.from_repo(repo) if repo.present?
      end

      nil
    end
  end
end
