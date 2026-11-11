# frozen_string_literal: true

module PackageToRepoMapping
  class NugetAmbiguousMatcher < Matcher
    # Paths where
    WHITELISTED_PATHS = %w[src/ nuget/ .nuspec/]
    self.certainty = Certainty::NUGET_INFERRED_NAMESPACE_MULTIPLE_MATCHES
    self.package_managers = [Types::PackageManager[:nuget]]

    def self.find_repo(package)
      repo = Repository.public_repos
               .left_joins(:star_count_assoc)
               .joins(:manifests)
               .merge(Manifest.where(
                        package_manager: package.package_manager,
                        name: package.name,
                      ))
               .merge(Manifest.at_root.or(Manifest.in_subdirectories(*WHITELISTED_PATHS)))
               .where("CAST(#{Manifest.table_name}.name AS BINARY) = ?", package.name)
               .order("#{StarCount.table_name}.star_count desc, github_repository_id asc")
               .limit(1)
               .first

      return RepoMatch.from_repo(repo) if repo.present?
    end
  end
end
