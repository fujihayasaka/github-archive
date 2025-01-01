module PackageToRepoMapping
  class Certainty
    # A GitHub staff member has overriden the mapping
    OVERRIDE                  = 90

    # A non-heuristic algorithm computed the repository authoritatively.
    POSITIVE_MATCH            = 85

    # The package repo metadata matches a corresponding manifest on GitHub
    MATCHING_MANIFEST         = 80

    # The package repo metadata matches information obtained from Clearly Defined service
    CLEARLY_DEFINED_MATCH     = 70

    # The package repo metadata is missing/inaccurate, but we found a single
    # manifest that seems to match the package.
    INFERRED_SINGLE_MATCH     = 55

    # The nuget package metadata is missing/inaccurate, but we found a multiple
    # manifests that match inside the root directory or whitelisted subsdirectories
    NUGET_INFERRED_NAMESPACE_MULTIPLE_MATCHES = 52

    # The maven package metadata is missing/inaccurate, but we found a multiple
    # manifests that match the same namespace at the root level of a repository
    # and also a manifest inside the repository that match.
    MAVEN_INFERRED_NAMESPACE_MULTIPLE_MATCHES = 51

    # The package repo metadata is missing/inaccurate, but we found multiple
    # manifests that seems to match and picked the most likely match.
    INFERRED_MULTIPLE_MATCHES = 50

    # The package repo metadata has a repository id, but that repository doesn't have the right manifest or doesn't exist in our database.
    UNVERIFIED                = 40

    # The package doesn't have repo metadata or doesn't live on GitHub.
    NULL                      = 0

    def self.minimum_required_for_display
      UNVERIFIED
    end
  end
end
