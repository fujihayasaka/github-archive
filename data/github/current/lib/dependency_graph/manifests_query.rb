# typed: true
# frozen_string_literal: true

module DependencyGraph
  class ManifestsQuery < Query
    FILTERS = {
      repository_id: {
        arg: :repositoryIds,
        type: :array,
      },
      manifest_id: {
        arg: :ids,
        type: :array,
      },
      with_dependencies: {
        arg: :withDependencies,
        type: :boolean,
      },
      with_snapshots: {
        arg: :withSnapshots,
        type: :boolean,
      },
      include_internal_snapshots: {
        arg: :includeInternalSnapshots,
        type: :boolean,
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
      package_manager: {
        arg: :packageManager,
        type: :enum,
      },
      package_name: {
        arg: :packageName,
      },
      license: {
        arg: :license,
      }
    }

    def initialize(manifest_filter:, dependencies_filter: {}, include_dependencies: false, backend: nil)
      @manifest_filter      = manifest_filter
      @dependencies_filter  = dependencies_filter
      @include_dependencies = include_dependencies
      super(backend: backend)
    end

    def results
      execute_query.map do |response|
        edges = response["data"]["manifests"]["edges"]
        page_info = response["data"]["manifests"]["pageInfo"]
        total_count = response["data"]["manifests"]["totalCount"]
        manifests = Manifest.wrap(edges, @dependencies_filter)

        {
          manifests: manifests,
          page_info: page_info,
          total_count: total_count
        }
      end
    end

    def query(options = {})
      field(:manifests, {
        arguments: map_arguments(FILTERS, manifest_filter),
        selections: [
          field(:totalCount),
          field(:pageInfo, {
            selections: [
              field(:startCursor),
              field(:endCursor),
              field(:hasNextPage),
              field(:hasPreviousPage)
            ]
          }),
          field(:edges, {
            selections: [
              field(:node, {
                selections: selections,
              }),
            ],
          }),
        ],
      }.merge(options))
    end

    private

    attr_reader :manifest_filter, :dependencies_filter, :include_dependencies

    def selections
      [
        field(:id),
        field(:repositoryId),
        field(:manifestType),
        field(:filename),
        field(:path),
        field(:isVendored),
        field(:source),
        field(:snapshotDetectorName),
        field(:snapshotScanned),
      ] + dependency_selections
    end

    def dependency_selections
      return [] unless include_dependencies?

      if include_dependencies == :count
        field = field(:dependencies, {
          arguments: [argument(:first, 0)],
          selections: [field(:totalCount)],
        })
      else
        field = field(:dependencies, {
          arguments: [
            argument(:first, dependencies_filter[:first]),
            argument(:after, dependencies_filter[:after]),
            argument(:prefer, dependencies_filter[:prefer]),
          ],
          selections: [
            field(:totalCount),
            field(:pageInfo, {
              selections: [
                field(:startCursor),
                field(:endCursor),
                field(:hasNextPage),
                field(:hasPreviousPage),
              ],
            }),
            field(:edges, {
              selections: [
                field(:cursor),
                field(:node, {
                  selections: [
                    field(:repositoryId),
                    field(:packageId),
                    field(:packageName),
                    field(:packageManager),
                    field(:requirements),
                    field(:hasDependencies),
                    field(:license),
                  ],
                }),
              ],
            }),
          ],
        })
      end

      [field]
    end

    def include_dependencies?
      @include_dependencies
    end
  end
end
