module PackageToRepoMapping
  class UnverifiedMatcher < Matcher
    self.certainty = Certainty::UNVERIFIED

    def self.find_repo(package)
      release = package.releases
        .published
        .where("repository_id is NOT NULL")
        .order("id desc")
        .select(:repository_id)
        .first

      RepoMatch.new(release.repository_id, release.repository_nwo) if release
    end
  end
end
