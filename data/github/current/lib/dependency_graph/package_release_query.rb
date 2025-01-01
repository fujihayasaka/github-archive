# typed: true
# frozen_string_literal: true

module DependencyGraph
  class PackageReleaseQuery < Query
    FILTERS = {
      package_name: {
        arg: :packageName,
      },
      package_manager: {
        arg: :packageManager,
        type: :enum,
      },
      requirements: {
        arg: :requirements,
      },
      default_to_latest: {
        arg: :defaultToLatest,
      },
      include_unpublished: {
        arg: :includeUnpublished,
      },
      first: {
        arg: :first,
      },
      after: {
        arg: :after,
      },
      preview: {
        arg: :preview,
        type: :boolean,
      },
    }

    def initialize(release_filter:, dependencies_filter:, include_dependencies: false, backend: nil)
      @release_filter       = release_filter
      @dependencies_filter  = dependencies_filter
      @include_dependencies = include_dependencies
      super(backend: backend)
    end

    def results
      execute_query
        .map { |response| response["data"]["packageReleases"]["edges"] }
        .map { |attributes| PackageRelease.wrap(attributes) }
    end

    def query(options = {})
      field(:packageReleases, {
        arguments: map_arguments(FILTERS, release_filter),
        selections: [
          field(:edges, {
            selections: [
              field(:node, {
                selections: [
                  field(:repositoryId),
                  field(:packageName),
                  field(:packageManager),
                  field(:version),
                  field(:publishedOn),
                  field(:license),
                  field(:clearlyDefinedScore),
                ] + dependency_selections,
              }),
            ],
          }),
        ],
      }.merge(options))
    end

    private

    attr_reader :release_filter, :dependencies_filter, :include_dependencies

    def dependency_selections
      return [] unless include_dependencies?

      field = field(:dependencies, {
        arguments: [
          argument(:first, dependencies_filter[:first]),
          argument(:after, dependencies_filter[:after]),
        ],
        selections: [
          field(:totalCount),
          field(:edges, {
            selections: [
              field(:node, {
                selections: [
                  field(:repositoryId),
                  field(:packageId),
                  field(:packageName),
                  field(:packageManager),
                  field(:requirements),
                  field(:hasDependencies),
                ],
              }),
            ],
          }),
        ],
      })

      [field]
    end

    def include_dependencies?
      @include_dependencies
    end
  end
end
