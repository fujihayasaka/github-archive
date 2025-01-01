# typed: true
# frozen_string_literal: true

require "test_helper"

module ApiInsights::Stats
  class RateLimitedSummaryFilterableTest < GitHub::TestCase
    setup do
      @filterable = FakeRateLimitedSummaryFilterable.new
    end

    test "adds rate limited summaries filter when value is true" do
      @filterable.with_rate_limited_summaries(true)
      refute_nil @filterable.query.summary_filters.find { |f| f.field == Queries::FilterField::RateLimitedRequestCount && f.operator == ">" && f.value == 0 }
    end

    test "adds rate limited summaries filter when value is false" do
      @filterable.with_rate_limited_summaries(false)
      refute_nil @filterable.query.summary_filters.find { |f| f.field == Queries::FilterField::RateLimitedRequestCount && f.operator == "==" && f.value == 0 }
    end

    test "does not add rate limited summaries filter when value is nil" do
      @filterable.with_rate_limited_summaries(nil)
      assert_nil @filterable.query.summary_filters.find { |f| f.field == Queries::FilterField::RateLimitedRequestCount }
    end
  end

  class FakeRateLimitedSummaryFilterable < StatsBase
    include RateLimitedSummaryFilterable

    def initialize
      now = Time.now.utc
      super 1, now - 1.day, now
    end

    def query
      super
    end
  end
end
