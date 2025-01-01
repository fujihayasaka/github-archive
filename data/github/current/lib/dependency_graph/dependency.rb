# typed: true
# frozen_string_literal: true

# Public: Domain object to wrap dependency graph API `Dependency` type
module DependencyGraph
  class Dependency
    attr_reader :cursor

    # @param manifest [DependencyGraph::Manifest] When this is present, we expose vulnerability alerts based on it.
    def self.wrap(dependencies, manifest:)
      Array(dependencies).map { |attrs| new(attrs["cursor"], attrs["node"], manifest: manifest) }
    end

    def initialize(cursor, attrs, manifest:)
      @cursor = cursor
      @attrs  = attrs
      @manifest = manifest
    end

    attr_reader :manifest

    def repository_id
      attrs["repositoryId"]
    end

    def license
      attrs["license"]
    end

    def package_id
      attrs["packageId"]
    end

    def package_name
      attrs["packageName"]
    end

    def package_manager
      attrs["packageManager"]
    end

    def requirements
      attrs["requirements"]
    end

    def scope
      attrs["scope"]
    end

    def human_requirements
      requirements.to_s
        .sub(/\A=\s+/, "")
        .gsub(/,(?=[^\s])/, ", ")
    end

    def has_dependencies?
      !!attrs["hasDependencies"]
    end

    def vulnerable_version_ranges
      return [] unless attrs["vulnerableVersionRanges"] &&
        attrs.dig("vulnerableVersionRanges", "edges").present?

      @vulnerable_version_ranges ||= attrs.dig("vulnerableVersionRanges", "edges").map do |range|
        DependencyGraph::Dependency::VulnerableVersionRange.new(range)
      end
    end

    def platform_type_name
      "DependencyGraphDependency"
    end

    def repository
      async_repository.sync
    end

    def async_repository
      return @async_repository if defined? @async_repository

      @async_repository = Platform::Loaders::ActiveRecord.load(::Repository, repository_id, security_violation_behaviour: :nil)
    end

    private

    attr_reader :attrs

    class VulnerableVersionRange
      def initialize(attrs)
        @attrs = attrs
      end

      def contained?
        attrs["isContained"]
      end

      def github_id
        attrs["node"]["githubId"]
      end

      private

      attr_reader :attrs
    end
  end
end
