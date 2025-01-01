# typed: strict
# frozen_string_literal: true

module ApiInsights::Stats
  module RateLimitedSummaryFilterable
    extend T::Helpers

    abstract!
    requires_ancestor { StatsBase }

    sig { params(value: T.nilable(T::Boolean)).returns(T.self_type) }
    def with_rate_limited_summaries(value)
      query.summary_filters << Queries::Filter.new(Queries::FilterField::RateLimitedRequestCount, 0, operator: value ? ">" : "==") unless value.nil?
      self
    end
  end
end
