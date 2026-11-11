# typed: true
# frozen_string_literal: true

module Search
  module Queries
    # DependabotAlertsAggregationsQuery is specialized for aggregation-only metrics queries.
    # Unlike DependabotAlertsFilterQuery (which only supports terms aggregations for filter options),
    # this class accepts arbitrary aggregation definitions — filter aggs, date_range aggs,
    # nested sub-aggs, etc. — needed by the security center metrics dashboard.
    #
    # Usage:
    #   query = DependabotAlertsAggregationsQuery.new(
    #     phrase: "is:closed severity:critical",
    #     scope: organization,
    #     current_user: user,
    #     cap_filter: cap_filter
    #   )
    #   result = query.execute
    #   result.aggregations  # => raw ES aggregations hash
    class DependabotAlertsAggregationsQuery < DependabotAlertsEsQuery
      QUERY_TIMEOUT = "1000ms"

      include RepositoriesData
      include AlertsFunnelData
      include ClosedAlertsByStateData
      include MostVulnerablePackage

      sig { params(opts: T::Hash[T.untyped, T.untyped], block: T.nilable(T.proc.params(query: Search::Query).void)).void }
      def initialize(opts = {}, &block)
        self.aggregations_hash = T.let(opts.delete(:aggregations_hash) || {}, T::Hash[T.untyped, T.untyped])

        super(
          **opts,
          per_page: 0,
          &block
        )
      end

      sig { params(value: T::Hash[T.untyped, T.untyped]).void }
      def aggregations_hash=(value)
        @aggregations_hash = value

        # reset memoized results data since the query definition has changed
        @results_total_count = nil
        @results_pruned = nil
      end

      # Construct an aggregation-only query document.
      sig { returns(T::Hash[T.untyped, T.untyped]) }
      def query_document
        {
          query: {
            bool: {
              filter: build_query_filter
            }
          },
          size: 0,
          aggregations: @aggregations_hash,
          runtime_mappings: build_runtime_mappings
        }
      end

      sig { override.returns(T::Hash[T.untyped, T.untyped]) }
      def query_params
        super.merge(timeout: QUERY_TIMEOUT)
      end
    end
  end
end
