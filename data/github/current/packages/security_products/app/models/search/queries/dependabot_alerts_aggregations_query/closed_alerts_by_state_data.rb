# typed: true
# frozen_string_literal: true

class Search::Queries::DependabotAlertsAggregationsQuery
  module ClosedAlertsByStateData
    extend T::Helpers

    requires_ancestor { Search::Queries::DependabotAlertsAggregationsQuery }

    CLOSED_STATES = T.let(%w[dismissed fixed auto_dismissed].freeze, T::Array[String])

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def closed_alerts_by_state
      thirty_days_ago = 30.days.ago.utc.iso8601

      self.aggregations_hash = {
        closed_by_period: {
          date_range: {
            field: "last_state_change_at",
            ranges: [
              { key: "before_30d", to: thirty_days_ago },
              { key: "past_30d", from: thirty_days_ago },
            ]
          },
          aggs: {
            by_state: { terms: { field: "state", size: 10 } }
          }
        }
      }

      result = execute
      period_buckets = result.aggregations.dig("closed_by_period", "buckets") || []

      past_30d_bucket = period_buckets.find { |b| b["key"] == "past_30d" } || {}
      before_30d_bucket = period_buckets.find { |b| b["key"] == "before_30d" } || {}

      # Extract per-state counts from the past 30 days
      state_buckets = past_30d_bucket.dig("by_state", "buckets") || []
      state_counts_map = state_buckets.each_with_object({}) { |b, h| h[b["key"]] = b["doc_count"] }

      closed_counts = CLOSED_STATES.each_with_object({}) do |state, hash|
        hash[state.to_sym] = state_counts_map[state] || 0
      end

      # Calculate percentage change
      closed_before_30d_count = before_30d_bucket["doc_count"] || 0
      closed_now_count = closed_before_30d_count + closed_counts.values.sum

      percentage_change = if closed_before_30d_count.zero?
        closed_now_count.positive? ? 100.00 : 0.00
      else
        ((closed_now_count - closed_before_30d_count) / closed_before_30d_count.to_f * 100).round(2)
      end

      closed_counts[:percentage_change_in_total_closed_alerts_past_30_days] = percentage_change
      closed_counts
    end
  end
end
