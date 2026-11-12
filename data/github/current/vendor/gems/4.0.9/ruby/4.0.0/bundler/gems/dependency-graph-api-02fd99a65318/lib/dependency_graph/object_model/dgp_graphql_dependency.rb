require "dependency_graph/object_model/base_graphql_dependency"

module DependencyGraph::ObjectModel
  class DGPGraphqlDependency < BaseGraphqlDependency

    def self.from_cache_payload(payload)
      raw_dep = Github::DependencyGraphPlatform::Graphql::V1::Dependency.decode(payload.fetch(:dependency_proto))
      dep = new(raw_dep, include_transitive_labels: true)
      dep.license = payload[:license]
      dep.has_dependencies = payload[:has_dependencies]
      dep.package_github_repository_id = payload[:package_github_repository_id]
      dep.package_github_repository_id_certainty = payload[:package_github_repository_id_certainty]
      dep.package_label = payload[:package_label]
      dep.package_id = payload[:package_id]
      dep
    end

    def initialize(dependency, include_transitive_labels:)
      super(dependency, include_transitive_labels: include_transitive_labels)
    end

    def cache_payload
      {
        source: "dgp",
        dependency_proto: Github::DependencyGraphPlatform::Graphql::V1::Dependency.encode(@dependency),
        license: license,
        has_dependencies: has_dependencies,
        package_github_repository_id: package_github_repository_id,
        package_github_repository_id_certainty: package_github_repository_id_certainty,
        package_label: package_label,
        package_id: package_id,
      }
    end

    def package_name
      @dependency.package_name
    end

    def package_manager
      @package_manager ||= Types::PackageManager.by(:dgp_ecosystem, @dependency.ecosystem) || Types::PackageManager::UNKNOWN
    end

    def package_url
      @package_url ||= PackageUrls::PackageUrl.from_package_release(package_manager: package_manager.human_name.downcase,
                                                                    name: package_name,
                                                                    version: requirements.exact_version).to_purl
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

    def relationship
      Types::Relationship.by(:api_value, @dependency.relationship) || Types::Relationship::UNKNOWN
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
