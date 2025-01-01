# typed: true
# frozen_string_literal: true

module DependencyGraph
  class UnmappedPackagesQuery < Query
    attr_reader :backend, :package_filter, :dependents_filter

    FILTERS = {
      names: {
        arg: :names,
      },
      package_manager: {
        arg: :packageManager,
        type: :enum,
      },
      first: {
        arg: :first,
      },
      limit: {
        arg: :limit,
      },
    }

    def initialize(package_filter:, dependents_filter: {}, include_dependents: false, include_dependent_counts: false, backend: nil)
      @backend                  = backend || default_backend
      @package_filter           = package_filter
      @dependents_filter        = dependents_filter
      @include_dependents       = include_dependents
      @include_dependent_counts = include_dependents || include_dependent_counts
    end

    def results
      data.map { |data| Package.wrap(data["unmappedPackages"]["edges"]) }
    end

    private

    def data
      execute_query.map { |results| results["data"] }
    end

    sig { override.params(options: T::Hash[T.untyped, T.untyped]).returns(T.untyped) }
    def query(options = {})
      field(:unmappedPackages, {
        arguments: map_arguments(FILTERS, package_filter),
        selections: [
          field(:edges, {
            selections: [
              field(:node, {
                selections: selections,
              }),
            ],
          }),
        ],
      })
    end

    def package_id?
      package_filter[:package_id].present?
    end

    def include_dependents?
      @include_dependents
    end

    def include_dependent_counts?
      @include_dependent_counts
    end

    def selections
      package_selections + dependent_counts_selections
    end

    def package_selections
      [
        field(:id),
        field(:name),
        field(:packageManager),
        field(:repositoryId),
        field(:packageManagerHumanName),
      ]
    end

    def dependent_counts_selections
      return [] unless include_dependent_counts?

      [
        field(:abstractRepositoryDependents, {
          selections: [
            field(:totalCount),
          ],
        }),
        field(:abstractPackageDependents, {
          selections: [
            field(:totalCount),
          ],
        }),
      ]
    end
  end
end
