module PackageToRepoMapping
  class WeakMatcher < Matcher
    self.certainty = Certainty::INFERRED_SINGLE_MATCH

    # Disable this matcher for maven & nuget because in Java and .NET
    # it is common to have manifests live outside the root directory.
    # This means that if we have some unrelated repo with a pom.xml in
    # the root directory, this match will override the correct match
    # for a subdirectory (which is the maven ambiguous matcher)
    self.package_managers = Types::PackageManager.to_a - [Types::PackageManager[:maven], Types::PackageManager[:nuget]]

    def self.find_repo(package)
      manifests =
        Manifest.where(
          package_manager: package.package_manager,
          name: package.label || package.name,
        )
        .where("CAST(#{Manifest.table_name}.name AS BINARY) = ?", package.label || package.name)
        .merge(Manifest.at_root)
        .limit(2)

      # if only one manifest has a matching name
      if manifests.count == 1 && manifests.first.repository.present?
        return RepoMatch.from_repo(manifests.first.repository)
      end
    end
  end
end
