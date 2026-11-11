# typed: true
# frozen_string_literal: true

class Search::Queries::DependabotAlertsAggregationsQuery
  module AlertsFunnelData
    extend T::Helpers

    requires_ancestor { Search::Queries::DependabotAlertsAggregationsQuery }

    # Maps funnel category names to ES filter clauses
    FUNNEL_CATEGORY_ES_FILTERS = T.let({
      "has:patch" => { term: { has_patch: true } },
      "severity:critical,high" => { terms: { severity: %w[critical high] } },
      "epss_percentage:>=0.01" => { range: { epss_percentage: { gte: 0.01 } } },
    }.freeze, T::Hash[String, T::Hash[T.untyped, T.untyped]])

    sig { params(funnel_category_order: T::Array[String]).returns(T::Hash[String, Integer]) }
    def alerts_funnel_data(funnel_category_order)
      # Build cumulative filter aggregations: each stage includes all preceding conditions
      aggregations_hash = {}
      cumulative_filters = T.let([], T::Array[T::Hash[T.untyped, T.untyped]])

      funnel_category_order.each_with_index do |category_name, index|
        cumulative_filters = cumulative_filters + [FUNNEL_CATEGORY_ES_FILTERS.fetch(category_name)]
        aggregations_hash[:"funnel_#{index}"] = {
          filter: { bool: { filter: cumulative_filters } }
        }
      end

      self.aggregations_hash = aggregations_hash
      result = execute
      total_count = result.total

      data = { "Matching alerts" => total_count }
      funnel_category_order.each_with_index do |category_name, index|
        data[category_name] = result.aggregations.dig("funnel_#{index}", "doc_count") || 0
      end

      data
    end
  end
end
