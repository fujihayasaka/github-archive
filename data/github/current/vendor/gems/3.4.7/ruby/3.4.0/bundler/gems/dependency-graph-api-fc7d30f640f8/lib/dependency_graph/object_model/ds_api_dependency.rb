require_relative "abstract_dependency"

module DependencyGraph
  module ObjectModel
    # This dependency corresponds to a Dependency Snapshots API dependency (Github::DependencySnapshotsApi::Dependency)
    class DSAPIDependency < AbstractDependency
      def initialize(dependency_name, dependency)
        # we don't currently care about dependency_name, but it is potentially interesting later.
        @dependency = dependency
        @package_url = PackageUrls::PackageUrl.from_purl(purl: @dependency.package_url)
      end

      attr_reader :dependency, :package_url

      def full_package_name
        @package_url.full_package_name
      end

      def requirement_set
        # For the time being, dependency snapshots capture an exact_version for packages, not a requirement set.
        #  We'll make sure that the version looks requirements set -ey in this method.
        version = @package_url.version.blank? ? "" : "= #{@package_url.version}"

        valid = true
        requirement_set = Versioning::RequirementSet.deserialize(
          version,
          allow_named_versions: Types::PackageManager.allows_named_versions?(package_manager),
          on_error: ->(range) {
            log_invalid_range(range)
            valid = false
          },
        )

        if valid
          requirement_set
        else
          Versioning::RequirementSet.wildcard
        end
      end

      def package_manager
        @package_url.type_dg_api
      end

      def scope
        case @dependency.scope
        when :SCOPE_RUNTIME
          "runtime"
        when :SCOPE_DEVELOPMENT
          "development"
        when :SCOPE_NONE
          ""
        else
          ""
        end
      end

      def relationship
        case @dependency.relationship
        when :RELATIONSHIP_DIRECT
          :RELATIONSHIP_DIRECT
        when :RELATIONSHIP_TRANSITIVE
          :RELATIONSHIP_INDIRECT
        when :RELATIONSHIP_UNKNOWN
          :RELATIONSHIP_UNKNOWN
        else
          :RELATIONSHIP_UNKNOWN
        end
      end

      def root_ancestors
        @dependency.root_ancestors.map do |root_ancestor|
          {
            package_name: root_ancestor.package_name,
            requirements: root_ancestor.requirements,
            relationship: map_ancestor_relationship(root_ancestor.relationship)
          }
        end
      end

      private
      def log_invalid_range(range)
        DependencyGraph.logger.info("invalid range from package_url replaced with wildcard",
          "gh.dependency_graph.dependency.package_url" => @dependency.package_url,
          "gh.dependency_graph.dependency.requirement_set" => range,
        )
      end

      def map_ancestor_relationship(relationship)
        case relationship
        when :ANCESTOR_RELATIONSHIP_PARENT
          DependencyGraphAPI::V1::SearchDependenciesForRepositoryResponse::AncestorRelationship::PARENT
        when :ANCESTOR_RELATIONSHIP_ANCESTOR
          DependencyGraphAPI::V1::SearchDependenciesForRepositoryResponse::AncestorRelationship::ANCESTOR
        else
          DependencyGraphAPI::V1::SearchDependenciesForRepositoryResponse::AncestorRelationship::UNKNOWN
        end
      end
    end
  end
end
