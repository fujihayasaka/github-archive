require "dependency_graph/object_model/base_graphql_dependency"

module DependencyGraph::ObjectModel
  class DGPGraphqlDependency < BaseGraphqlDependency

    def initialize(dependency, include_transitive_labels:)
      super(dependency, include_transitive_labels: include_transitive_labels)
    end

    def package_name
      @dependency.package_name
    end

    def package_manager
      @package_manager ||= Types::PackageManager.by(:dgp_ecosystem, @dependency.ecosystem) || Types::PackageManager::UNKNOWN
    end

    def requirements
      return @requirements if defined?(@requirements)

      valid = true
      requirement_set = Versioning::RequirementSet.deserialize(
        normalize_requirements(@dependency.requirements),
        allow_named_versions: Types::PackageManager.allows_named_versions?(package_manager),
        on_error: ->(range) {
          log_invalid_range(range)
          valid = false
        },
      )

      @requirements = valid ? requirement_set : Versioning::RequirementSet.wildcard
    end

    private

    def normalize_requirements(requirements)
      case package_manager
      when Types::PackageManager::NPM
        ManifestAdapters::Npm::Requirements.new(requirements).normalize
      else
        # only NPM is supported for now
        requirements
      end
    end

    def log_invalid_range(range)
      DependencyGraph.logger.info("invalid requirements for dgp dependency replaced with wildcard",
        "gh.dependency_graph.dependency.package_manager" => package_manager,
        "gh.dependency_graph.dependency.package_name" => package_name,
        "gh.dependency_graph.dependency.requirements" => range,
      )
    end
  end
end
