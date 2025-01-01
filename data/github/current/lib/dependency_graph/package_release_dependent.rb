# typed: true
# frozen_string_literal: true

# Public: Domain object to wrap dependency graph API `PackageReleaseDependent` type
module DependencyGraph
  class PackageReleaseDependent
    def self.wrap(package_release_dependents)
      package_release_dependents.map { |attrs| new(attrs["node"]) }
    end

    def initialize(attrs)
      @attrs = attrs
    end

    def package_release
      @package_release ||= PackageRelease.new(attrs["packageRelease"])
    end

    def dependents_count
      attrs["dependentsCount"]
    end

    def vulnerabilities_count
      attrs["vulnerabilitiesCount"]
    end

    def lower_version_count
      attrs["dependents"]["lowerVersionCount"]
    end

    def upper_version_count
      attrs["dependents"]["upperVersionCount"]
    end

    def dependents
      @dependents ||= DependencyGraph::Dependent.wrap(attrs["dependents"]["edges"])
    end

    def dependents_page_info
      @dependents_page_info ||= Platform::ConnectionWrappers::PageInfo.new(
        has_next_page: attrs["dependents"]["pageInfo"]["hasNextPage"],
        has_previous_page: attrs["dependents"]["pageInfo"]["hasPreviousPage"],
        start_cursor: attrs["dependents"]["pageInfo"]["startCursor"],
        end_cursor: attrs["dependents"]["pageInfo"]["endCursor"],
      )
    end

    attr_reader :attrs
  end
end
