require "dependency_graph/object_model/base_graphql_dependency"

module DependencyGraph::ObjectModel
  class DSGraphqlDependency < BaseGraphqlDependency

    def initialize(dependency, include_transitive_labels:)
      super(dependency, include_transitive_labels: include_transitive_labels)
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
