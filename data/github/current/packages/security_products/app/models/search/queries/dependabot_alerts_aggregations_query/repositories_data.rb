# typed: true
# frozen_string_literal: true

class Search::Queries::DependabotAlertsAggregationsQuery
  module RepositoriesData
    extend T::Helpers

    requires_ancestor { Search::Queries::DependabotAlertsAggregationsQuery }

    # Maps JSON sort field names to ES aggregation order paths
    REPOSITORIES_SORT_MAP = T.let({
      countOpen:     "_count",
      countCritical: "count_critical._count",
      countHigh:     "count_high._count",
      countMedium:   "count_medium._count",
      countLow:      "count_low._count",
      countEPSS:     "count_epss._count",
    }.freeze, T::Hash[Symbol, String])


    sig do
      params(
        cursor: Integer,
        sort_by: Symbol,
        sort_dir: Symbol,
        per_page: Integer
      ).returns(T::Array[T::Hash[Symbol, T.untyped]])
    end
    def repositories_data(cursor: 0, sort_by: :countOpen, sort_dir: :desc, per_page: 20)
      self.aggregations_hash = {
        by_repository: {
          terms: {
            field: "repository_id",
            size: cursor + per_page + 1,
            order: [{ REPOSITORIES_SORT_MAP[sort_by] => sort_dir.to_s }, { "_key" => "asc" }]
          },
          aggs: {
            count_critical: { filter: { term: { severity: "critical" } } },
            count_high:     { filter: { term: { severity: "high" } } },
            count_medium:   { filter: { term: { severity: "moderate" } } },
            count_low:      { filter: { term: { severity: "low" } } },
            count_epss:     { filter: { range: { epss_percentage: { gte: 0.01 } } } },
          }
        }
      }

      result = execute
      buckets = result.aggregations.dig("by_repository", "buckets") || []

      # Apply cursor-based pagination by dropping leading buckets
      paged_buckets = buckets.drop(cursor)

      # Hydrate repository data from DB
      repo_ids = paged_buckets.map { |b| b["key"] }
      repo_by_id = Repository.where(id: repo_ids).index_by(&:id)

      paged_buckets.filter_map do |bucket|
        repo = repo_by_id[bucket["key"]]
        next unless repo

        {
          id:            repo.name_with_display_owner,
          displayName:   repo.name,
          href:          UrlHelpers.repository_alerts_path(repo.owner_display_login, repo),
          countOpen:     bucket["doc_count"],
          countEPSS:     bucket.dig("count_epss", "doc_count") || 0,
          countCritical: bucket.dig("count_critical", "doc_count") || 0,
          countHigh:     bucket.dig("count_high", "doc_count") || 0,
          countMedium:   bucket.dig("count_medium", "doc_count") || 0,
          countLow:      bucket.dig("count_low", "doc_count") || 0,
          repo_id:       bucket["key"]
        }
      end
    end
  end
end
