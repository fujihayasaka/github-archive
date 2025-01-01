# typed: true
# frozen_string_literal: true

module DependencyGraph
  class RepositoryPackageReleaseQuery < Query
    RELEASE_FILTERS = {
      owner_ids: {
        arg: :ownerIds,
        type: :array,
      },
      package_manager: {
        arg: :packageManager,
        type: :enum,
      },
      package_name: {
        arg: :name,
      },
      exact_match: {
        arg: :exactMatch,
        type: :boolean,
      },
      package_version: {
        arg: :version,
      },
      only_vulnerable_packages: {
        arg: :vulnerable,
        type: :boolean,
      },
      severity: {
        arg: :severity,
        type: :enum,
      },
      licenses: {
        arg: :license,
        type: :enum_array,
      },
      first: {
        arg: :first,
      },
      last: {
        arg: :last,
      },
      before: {
        arg: :before,
      },
      after: {
        arg: :after,
      },
      preview: {
        arg: :preview,
        type: :boolean,
      },
      sort_by: {
        arg: :sortBy,
        type: :enum,
      },
    }

    DEPENDENTS_FILTERS = {
      owner_ids: {
        arg: :ownerIds,
        type: :array,
      },
      dependent_name: {
        arg: :dependentName,
        type: :string,
      },
      first: {
        arg: :first,
      },
      last: {
        arg: :last,
      },
      before: {
        arg: :before,
      },
      after: {
        arg: :after,
      },
    }

    def initialize(release_filter:, dependents_filter: nil, include_dependent_version_counts: false, backend: nil)
      @release_filter = release_filter
      @dependents_filter = dependents_filter
      @include_dependent_version_counts = include_dependent_version_counts
      super(backend: backend)
    end

    def results
      execute_query.map do |response|
        page_info = response["data"]["repositoryPackageReleases"]["pageInfo"]
        edges = response["data"]["repositoryPackageReleases"]["edges"]
        total_count = response["data"]["repositoryPackageReleases"]["totalCount"]
        {
          page_info: page_info,
          dependents: PackageReleaseDependent.wrap(edges),
          total_count: total_count,
        }
      end
    end

    def node_fields
      fields = [
        field(:packageRelease, {
          selections: [
            field(:repositoryId),
            field(:packageName),
            field(:packageManager),
            field(:publishedOn),
            field(:version),
            field(:license),
          ],
        }),
        field(:dependentsCount),
        field(:vulnerabilitiesCount),
      ]

      if @dependents_filter
        selections = []

        # Select edge fields if we are selecting some number of dependents
        if @dependents_filter[:first] || @dependents_filter[:last]
          selections << field(:edges, {
            selections: [
              field(:node, {
                selections: [
                  field(:manifestFilename),
                  field(:manifestPath),
                  field(:packageName, field_alias: :name),
                  field(:repositoryId),
                ],
              }),
            ],
          })

          selections << field(:pageInfo, {
            selections: [
              field(:hasNextPage),
              field(:hasPreviousPage),
              field(:startCursor),
              field(:endCursor),
            ],
          })
        end

        if @include_dependent_version_counts
          selections << field(:lowerVersionCount)
          selections << field(:upperVersionCount)
        end

        fields << field(:dependents, {
          arguments: map_arguments(DEPENDENTS_FILTERS, @dependents_filter),
          selections: selections,
        })
      end

      fields
    end

    def query(options = {})
      field(:repositoryPackageReleases, {
        arguments: map_arguments(RELEASE_FILTERS, @release_filter),
        selections: [
          field(:edges, {
            selections: [
              field(:node, { selections: node_fields }),
            ],
          }),
          field(:totalCount),
          field(:pageInfo, {
            selections: [
              field(:hasNextPage),
              field(:hasPreviousPage),
              field(:startCursor),
              field(:endCursor),
            ],
          }),
        ],
      }.merge(options))
    end
  end
end
