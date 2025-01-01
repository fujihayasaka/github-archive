module DependencyGraph::ObjectModel
  # Why "abstract dependency"? It's a pre-refactoring encapsulation of how the different
  # dependencies we have are different, and it's meant to allow us to write
  # common code (like vulnerability lookup) that can be reused across very different
  # dependency sources (like parsedmanifest, ds-api, etc. )
  class AbstractDependency
    # The full package name (in PURL terms, namespace + name combined however the ecosystem prefers it)
    def full_package_name
      raise NotImplementedError.new("Abstract method called!")
    end

    # The requirement set that comprises the version specification for this dependency.
    # Some dependency implementors only have exact versions today, which is an almost-redundant requirement set.
    def requirement_set
      raise NotImplementedError.new("Abstract method called!")
    end

    # Package_manager for the individual dependency
    def package_manager
      raise NotImplementedError.new("Abstract method called!")
    end

    def scope
      raise NotImplementedError.new("Scope called!")
    end

    # default the relationship to unknown. Other options are :RELATIONSHIP_DIRECT and :RELATIONSHIP_INDIRECT
    def relationship
      :RELATIONSHIP_UNKNOWN
    end

    def to_proto(vulnerabilities_hash_by_dependency, include_relationship: false)
      best_exact_version = get_exact_version_from_requirement_set(requirement_set)
      DependencyGraphAPI::V1::Manifest::Dependency.new(
        name: full_package_name,
        exact_version: best_exact_version,
        requirements: requirement_set.serialize,
        has_loaded_vulnerable_version_ranges: true,
        package_manager: package_manager.to_proto,
        scope: scope.to_s,
        relationship: include_relationship ? relationship : :RELATIONSHIP_UNKNOWN,
        vulnerable_version_ranges:
          if vulnerabilities_hash_by_dependency.has_key?(self)
            vulnerabilities_hash_by_dependency[self].map do |vvr|
              DependencyGraphAPI::V1::Manifest::Dependency::VulnerableVersionRange.new(
                github_id: vvr.github_id,
                is_contained: vvr.requirements_set.contain?(requirement_set),
              )
            end
          else
            []
          end
      )
    end

    private

    def get_exact_version_from_requirement_set(requirement_set)
      return requirement_set.exact_version if requirement_set.present? && requirement_set.exact_version.present?
    end
  end
end
