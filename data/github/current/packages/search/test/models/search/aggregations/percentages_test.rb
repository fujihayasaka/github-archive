# typed: true
# frozen_string_literal: true

require "test_helper"

class SearchAggregationsPercentagesTest < GitHub::TestCase
  setup do
    @terms = [
      { "key" => "C",     "doc_count" => 25 },
      { "key" => "PHP",   "doc_count" => 50 },
      { "key" => "Ruby",  "doc_count" => 100 },
      { "key" => "Swift", "doc_count" => 5 },
    ]
    aggregation = {
      "buckets" => @terms,
      "doc_count_error_upper_bound" => 0,
      "sum_other_doc_count" => 1,
    }

    @terms_aggregation = Search::Aggregations::Terms.new(aggregation)
    @languages = Search::Aggregations::Percentages.build(@terms_aggregation)
  end

  test "converts terms to term count" do
    @languages.each do |term|
      assert_instance_of Search::Aggregations::Percentages::TermCount, term
    end
  end

  test "looks up linguist language" do
    @languages.each do |term|
      language = Linguist::Language[term.term]
      assert_equal term.language, language
    end
  end

  test "calculates percentage" do
    percentages = @languages.sort_by(&:term).collect(&:percentage)
    assert_equal [14, 28, 55, 3], percentages
  end
end
