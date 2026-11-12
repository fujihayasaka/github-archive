require "dependency_graph/object_model/base_graphql_dependency"

module DependencyGraph::ObjectModel
  class DSGraphqlDependency < BaseGraphqlDependency

    def self.from_cache_payload(payload)
      raw_dep = Github::DependencySnapshotsApi::Manifest::Dependency.decode(payload.fetch(:dependency_proto))
      ds_api_dep = DSAPIDependency.new("", raw_dep)
      dep = new(ds_api_dep, include_transitive_labels: true)
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
        source: "snapshots",
        dependency_proto: Github::DependencySnapshotsApi::Manifest::Dependency.encode(@dependency.dependency),
        license: license,
        has_dependencies: has_dependencies,
        package_github_repository_id: package_github_repository_id,
        package_github_repository_id_certainty: package_github_repository_id_certainty,
        package_label: package_label,
        package_id: package_id,
      }
    end

    def package_name
      @dependency.full_package_name
    end

    def package_manager
      @dependency.package_manager
    end

    def package_url
      @dependency.respond_to?(:package_url) ? @dependency.package_url&.to_purl : nil
    end

    def requirements
      @dependency.requirement_set
    end
  end
end
