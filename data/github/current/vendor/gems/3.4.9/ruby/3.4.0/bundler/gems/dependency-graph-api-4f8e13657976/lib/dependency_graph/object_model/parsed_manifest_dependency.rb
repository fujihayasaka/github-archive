module DependencyGraph::ObjectModel
  # This manifest corresponds to Dependency Graph API's ParsedManifest.UnindexedDependency model, used as a non-stored result of a file parse
  class ParsedManifestDependency < AbstractDependency
    def initialize(dependency)
      @dependency = dependency
      @requirement_set = Versioning::RequirementSet.deserialize @dependency.requirements, allow_named_versions: Types::PackageManager.allows_named_versions?(package_manager)
    end

    def full_package_name
      @dependency.package_name
    end

    def requirement_set
      @requirement_set
    end

    def package_manager
      @dependency.package_manager
    end

    def scope
      @dependency.scope
    end
  end
end
