# typed: true
# frozen_string_literal: true

module DependencyGraph
  class PackagesQuery < Query
    FILTERS = {
      repository_id: {
        arg: :repositoryIds,
        type: :array,
      },
      names: {
        arg: :names,
      },
      package_manager: {
        arg: :packageManager,
        type: :enum,
      },
      package_id: {
        arg: :id,
      },
      first: {
        arg: :first,
      },
      after: {
        arg: :after,
      },
      last: {
        arg: :last,
      },
      before: {
        arg: :before,
      },
      debug: {
        arg: :debug,
      },
      preview: {
        arg: :preview,
        type: :boolean,
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
      if package_id?
        data.map { |data| Package.wrap([data]) }
      else
        data.map { |data| Package.wrap(data["packages"]["edges"]) }
      end
    end

    private

    attr_reader :backend, :package_filter, :dependents_filter

    def data
      execute_query.map { |results| results["data"] }
    end

    sig { override.params(options: T::Hash[T.untyped, T.untyped]).returns(T.untyped) }
    def query(options = {})
      if package_id?
        field(:node, {
          arguments: map_arguments(FILTERS, package_filter.slice(:package_id)),
          selections: [
            inline_fragment(type_name("Package"), {
              selections: selections,
            }),
          ],
        })
      else
        field(:packages, {
          arguments: map_arguments(FILTERS, package_filter.except(:package_id)),
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
    end

    def package_id?
      package_filter[:package_id].present?
    end

    def include_debug?
      @package_filter[:debug]
    end

    def include_dependents?
      @include_dependents
    end

    def include_dependent_counts?
      @include_dependent_counts
    end

    def selections
      package_selections + dependent_counts_selections + dependents_selections + debug_selections
    end

    def package_selections
      [
        field(:id),
        field(:name),
        field(:repositoryId),
        field(:packageManager),
        field(:packageManagerHumanName),
      ]
    end

    def dependent_counts_selections
      return [] unless include_dependent_counts?

      [
        field(:abstractRepositoryDependents, {
          arguments: [dependents_owner_id_argument].compact,
          selections: [
            field(:totalCount),
          ],
        }),
        field(:abstractPackageDependents, {
          arguments: [dependents_owner_id_argument].compact,
          selections: [
            field(:totalCount),
          ],
        }),
      ]
    end

    def debug_selections
      return [] unless include_debug?

      [
        field(:debugAssociationExplanation),
        field(:debugShouldBeAssociatedToRepo),
      ]
    end

    def dependents_selections
      return [] unless include_dependents?

      [
        field(dependents_field, {
          field_alias: :dependents,
          arguments: Array(dependents_arguments),
          selections: [
            field(:edges, {
              selections: [
                field(:cursor),
                field(:node, {
                  selections: [
                    field(:name),
                    field(:repositoryId),
                  ],
                }),
              ],
            }),
            field(:pageInfo, {
              selections: [
                field(:hasPreviousPage),
                field(:hasNextPage),
              ],
            }),
          ],
        }),
      ]
    end

    def dependents_arguments
      args = if dependents_filter[:first].present?
        [
          argument(:first, dependents_filter[:first]),
          argument(:after, dependents_filter[:after]),
        ]
      elsif dependents_filter[:last].present?
        [
          argument(:last, dependents_filter[:last]),
          argument(:before, dependents_filter[:before]),
        ]
      end
      T.must(args) << dependents_owner_id_argument if dependents_owner_id_argument
      args
    end

    def dependents_owner_id_argument
      return @dependents_owner_id_argument if defined?(@dependents_owner_id_argument)
      @dependents_owner_id_argument = if dependents_filter[:owner_id]
        argument(:ownerId, dependents_filter[:owner_id])
      end
    end

    def dependents_field
      case dependents_filter[:type]
      when :package then :abstractPackageDependents
      when :repository then :abstractRepositoryDependents
      else
        raise "Invalid dependent type '#{dependents_filter[:type].inspect}"
      end
    end
  end
end
