# typed: true
# frozen_string_literal: true

module DependencyGraph
  class AllRepositoriesWithVersionRangeQuery < Query
    include AllRepositoriesWithVersionRangeQueryInterface
    include Scientist

    # Returns *all* (public and *private*) repositories that contain a
    # manifest with a given version range. Used for vulnerability
    # alerting.

    FILTERS = {
      package_manager: {
        arg: :packageManager,
        type: :enum,
      },
      package_name: {
        arg: :packageName,
      },
      requirements: {
        arg: :requirements,
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
      }
    }

    def initialize(dependents_filter:, backend: nil, timeout: Client::REQUEST_TIMEOUT)
      @dependents_filter = dependents_filter
      super(backend: backend || default_backend(timeout: timeout))
    end

    # NOTE: Avoid new uses of this method
    #
    # This method is not compatible with the DependencyGraphPlatform version of this class, it is left in place
    # due to a significant number of legacy tests that test via or stub based on this method.
    #
    # Prefer to use methods that are part of AllRepositoriesWithVersionRangeQueryInterface, in this case
    # alertable_dependents should be preferred.
    sig { returns(GitHub::Result) }
    def results
      executed_dependent_edges.map { |edges| Dependent.wrap(edges) }
    end

    sig { override.returns(T::Array[DependencyGraph::Alerting::AlertableDependent]) }
    def alertable_dependents
      results.value!
    end

    sig { override.void }
    def execute_query!
      executed_results
    end

    sig { override.returns(T.nilable(String)) }
    def last_cursor
      executed_dependent_edges.map { |edges| edges.last&.fetch("cursor", nil) }.value!
    end

    sig { override.returns(T.nilable(String)) }
    def dependent_end_cursor
      executed_results
        .map { |response| response.dig("data", "allRepositoriesWithVersionRange", "dependentEndCursor") }
        .value!
    end

    sig { override.returns(T.nilable(T::Boolean)) }
    def has_next?
      executed_results
        .map { |response| response["data"]["allRepositoriesWithVersionRange"]["pageInfo"]["hasNextPage"] }
        .value!
    end

    def query(options = {})
      field(:allRepositoriesWithVersionRange, {
        arguments: map_arguments(FILTERS, dependents_filter),
        selections: [
          field(:edges, {
            selections: [
              field(:cursor),
              field(:node, {
                selections: [
                  field(:repositoryId),
                  field(:manifestPath),
                  field(:manifestFilename),
                  field(:requirements),
                  field(:scope),
                ],
              }),
            ],
          }),
          field(:pageInfo, {
            selections: [
              field(:hasNextPage),
            ],
          }),
          field(:dependentEndCursor),
        ],
      }.merge(options))
    end

    private

    attr_reader :dependents_filter

    def executed_dependent_edges
      executed_results
        .map { |response| response["data"]["allRepositoriesWithVersionRange"]["edges"] }
    end

    def executed_results
      @executed_results ||= execute_query(query)
    end
  end
end
