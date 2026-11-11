# typed: true
# frozen_string_literal: true

# Public: Domain object to wrap dependency graph API `PackageRelease` type
module DependencyGraph
  class PackageRelease
    def self.wrap(package_releases)
      package_releases.map { |attrs| new(attrs["node"]) }
    end

    def initialize(attrs)
      @attrs = attrs
    end

    def repository_id
      attrs["repositoryId"]
    end

    def package_name
      attrs["packageName"]
    end

    def package_manager
      attrs["packageManager"]
    end

    def published_on
      attrs["publishedOn"]
    end

    def version
      attrs["version"]
    end

    def license
      attrs["license"]
    end

    def dependencies_count
      attrs.dig("dependencies", "totalCount")
    end

    def dependencies_cursor
      dependencies.last.cursor
    end

    def dependencies
      @dependencies ||= Dependency.wrap(attrs.dig("dependencies", "edges"), manifest: nil)
    end

    def clearly_defined_score
      attrs["clearlyDefinedScore"]
    end

    def platform_type_name
      "DependencyGraphPackageRelease"
    end

    def repository
      async_repository.sync
    end

    def async_repository
      return @async_repository if defined? @async_repository

      @async_repository = Platform::Loaders::ActiveRecord.load(::Repository, repository_id, security_violation_behaviour: :nil)
    end

    def external_package_manager_url
      DependencyGraph::PackageUrlBuilder.external_url(
        package_manager: package_manager,
        package_name: package_name
      )
    end

    private

    attr_reader :attrs
  end
end
