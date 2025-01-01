module DependencyGraph::ObjectModel
  # Adapter for returning manifest dependencies to graphql
  # Note this does not inherit from AbstractDependency but rather wraps its
  # subclasses. This can be removed once we stop using graphql to show
  # dependencies on dotcom.
  class BaseGraphqlDependency
    attr_accessor :license, :has_dependencies, :package_github_repository_id, :package_github_repository_id_certainty, :package_label, :package_id

    def initialize(dependency, include_transitive_labels:)
      @include_transitive_labels = include_transitive_labels
      @dependency = dependency
    end

    def has_dependencies?
      has_dependencies || false
    end

    def package_url
      nil
    end

    def scope
      nil
    end

    def relationship
      return nil unless @include_transitive_labels

      @dependency.relationship
    end

    def vulnerable_version_ranges
      nil
    end
  end
end
