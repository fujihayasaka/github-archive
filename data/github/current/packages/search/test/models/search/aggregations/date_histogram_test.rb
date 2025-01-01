# typed: true
# frozen_string_literal: true

require "test_helper"

class SearchAggregationsDateHistogramTest < GitHub::TestCase
  setup do
    @entries = [
      { "time" => 1400271913, "count" => 1 },
      { "time" => 1400281913, "count" => 2 },
    ]

    @aggregation = Search::Aggregations::DateHistogram.new("buckets" => @entries)
  end

  test "can export to json" do
    assert_equal @entries, @aggregation.as_json
  end
end
