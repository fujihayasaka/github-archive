# typed: true
# frozen_string_literal: true

require "test_helper"

module ApiInsights::Stats
  class RouteStatsTest < GitHub::TestCase
    def setup
      @route_stats = TestableRouteStats.new
    end

    test "initialization sets correct summary_key_fields" do
      assert_includes @route_stats.query.summary_key_fields, Queries::SummaryKeyField::HttpMethod
      assert_includes @route_stats.query.summary_key_fields, Queries::SummaryKeyField::ApiRoute
    end

    test "with_api_route_prefix adds correct filter" do
      api_route_prefix = "/api/v1"
      @route_stats.with_api_route_prefix(api_route_prefix)
      filter = @route_stats.query.filters.find { |f| f.field == Queries::FilterField::ApiRoute }
      refute_nil filter
      assert_equal api_route_prefix, filter.value
      assert_equal "startswith", filter.operator
    end

    test "valid_sort_field? returns true for valid fields" do
      assert @route_stats.send(:valid_sort_field?, Queries::SortField::HttpMethod)
      assert @route_stats.send(:valid_sort_field?, Queries::SortField::ApiRoute)
    end
  end

  class TestableRouteStats < RouteStats
    def initialize
      now = Time.now.utc
      super 1, now - 1.day, now
    end

    def query
      super
    end
  end
end
