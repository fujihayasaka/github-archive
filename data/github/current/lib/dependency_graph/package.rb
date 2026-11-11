# typed: true
# frozen_string_literal: true

# Public: Domain object to wrap dependency graph API `Package` type
module DependencyGraph
  class Package
    def self.wrap(packages)
      packages.map { |attrs| new(attrs["node"]) }
    end

    def initialize(attrs)
      @attrs = attrs
    end

    def id
      attrs["id"]
    end

    def name
      attrs["name"]
    end

    def repository_id
      attrs["repositoryId"]
    end

    def package_manager
      attrs["packageManager"]
    end

    def package_manager_human_name
      attrs["packageManagerHumanName"]
    end

    def repository_dependents_count
      attrs.dig("abstractRepositoryDependents", "totalCount").to_i
    end

    def package_dependents_count
      attrs.dig("abstractPackageDependents", "totalCount").to_i
    end

    def dependents
      @dependents ||= Dependent.wrap(Array(attrs.dig("dependents", "edges")))
    end

    def has_previous_dependents_page?
      attrs.dig("dependents", "pageInfo", "hasPreviousPage")
    end

    def has_next_dependents_page?
      attrs.dig("dependents", "pageInfo", "hasNextPage")
    end

    def dependents_start_cursor
      dependents.first&.cursor
    end

    def dependents_end_cursor
      dependents.last&.cursor
    end

    def platform_type_name
      "DependencyGraphPackage"
    end

    def debug_should_be_associated_to_repo
      attrs["debugShouldBeAssociatedToRepo"]
    end

    def debug_association_explanation
      attrs["debugAssociationExplanation"]
    end

    def dependents_page_info
      Platform::ConnectionWrappers::PageInfo.new(
        start_cursor:      dependents_start_cursor,
        has_previous_page: has_previous_dependents_page?,
        has_next_page:     has_next_dependents_page?,
        end_cursor:        dependents_end_cursor,
      )
    end

    def load_dependent_repositories(viewer)
      Platform::Security::RepositoryAccess.with_viewer(viewer) do
        Promise.all(dependents.compact.map(&:async_repository)).sync
      end
    end

    private

    attr_reader :attrs
  end
end
