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
      return unless package_name.present? && package_manager.present?

      case package_manager
      when "NUGET"
        Addressable::Template.new("https://www.nuget.org/packages/{package}").expand(package: package_name)
      when "PIP"
        Addressable::Template.new("https://pypi.org/project/{package}").expand(package: package_name)
      when "NPM"
        Addressable::Template.new("https://www.npmjs.com/package/{package}").expand(package: package_name)
      when "RUBYGEMS"
        Addressable::Template.new("https://rubygems.org/gems/{package}").expand(package: package_name)
      when "MAVEN"
        # maven url for a package splits package name into group and artifact id
        org_id, artifact_id = package_name.split(":")
        Addressable::Template.new("https://search.maven.org/artifact/{org_id}/{artifact_id}").expand(org_id: org_id, artifact_id: artifact_id)
      when "COMPOSER"
        Addressable::Template.new("https://packagist.org/packages/{package}").expand(package: package_name)
      else
        # Package Manager for Package has not yet been defined
        nil
      end
    end

    private

    attr_reader :attrs
  end
end
