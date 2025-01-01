# typed: true
# frozen_string_literal: true

require "test_helper"

class SearchAggregationsTermsTest < GitHub::TestCase
  setup do
    @terms = [
      { "key" => "US", "doc_count" => 1 },
      { "key" => "AU", "doc_count" => 2 },
    ]
    aggregation = {
      "buckets" => @terms,
      "doc_count_error_upper_bound" => 0,
      "sum_other_doc_count" => 1,
    }

    @aggregation = Search::Aggregations::Terms.new(aggregation)
  end

  test "valid representation" do
    assert_equal @terms, @aggregation.terms
    assert_equal 4, @aggregation.total
    assert_equal 1, @aggregation.other
  end

  test "can export to json" do
    json = @aggregation.as_json

    assert_equal 1, json["US"]
    assert_equal 2, json["AU"]
  end
end
