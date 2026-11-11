# typed: true
# frozen_string_literal: true

class Search::Queries::DependabotAlertsAggregationsQuery
  module MostVulnerablePackage
    extend T::Helpers

    requires_ancestor { Search::Queries::DependabotAlertsAggregationsQuery }

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def most_vulnerable_package
      self.aggregations_hash = {
        by_package: {
          terms: { field: "package_name", size: 1, shard_size: 20, show_term_doc_count_error: true }
        }
      }

      # To get an exact count of alerts for the most vulnerable package, we may need to perform two queries
      # if the most vulnerable package wasn't within the top shard_size results on a subset of shards.
      # This is indicated by a non-zero "doc_count_error_upper_bound" value returned by the terms aggregation.
      # 1. Query for the most vulnerable package name using the terms agg (which may return an inaccurate doc_count)
      # 2. Add a filter on the most vulnerable package name and query for the exact count

      result = execute
      bucket = result.aggregations.dig("by_package", "buckets")&.first
      return {} if bucket.nil?

      has_uncounted_results = result.aggregations.dig("by_package", "doc_count_error_upper_bound").to_i > 0
      package_name = bucket["key"]
      return { package_name: package_name, alert_count: bucket["doc_count"] } unless has_uncounted_results

      # setting the phrase resets memoized query and filter values
      self.phrase = [self.phrase, "package:#{package_name}"].join(" ")
      self.aggregations_hash = {} # no need for aggs in this query, we only want the count of alerts for the package

      package_value_count = execute.total

      {
        package_name: package_name,
        alert_count: package_value_count,
      }
    end
  end
end
