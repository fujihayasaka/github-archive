module DependencyGraph::ObjectModel
  # This manifest corresponds to Dependency Graph API's "Manifest Dependency" model, used as the target model for storage of ParsedManifests
  class DBDependency < AbstractDependency
    def initialize(dependency)
      @dependency = dependency
      @requirement_set = Versioning::RequirementSet.deserialize(@dependency.requirements, allow_named_versions: @dependency.package_manager.allows_named_versions)
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
