# typed: true
# frozen_string_literal: true

require "test_helper"

class SearchFiltersQueryFilterTest < GitHub::TestCase
  setup do
    @quals = Search::ParsedQuery.qualifiers
  end

  test "query filter" do
    @quals[:location].must "Boulder, CO"
    filter = Search::Filters::QueryFilter.new field: :location, qualifiers: @quals
    assert_equal({ query_string: { query: "Boulder, CO", default_field: :location, default_operator: :AND } }, filter.must)
  end

  test "escaping special Lucene characters" do
    @quals[:location].must "Denton *TX"
    filter = Search::Filters::QueryFilter.new field: :location, qualifiers: @quals
    assert_equal({ query_string: { query: 'Denton \\*TX', default_field: :location, default_operator: :AND } }, filter.must)
  end

  test "empty query value" do
    filter = Search::Filters::QueryFilter.new field: :location, qualifiers: @quals
    assert_nil filter.must
  end

  test "array of query values" do
    @quals[:location].must "Boulder, CO"
    @quals[:location].must "San Francisco"
    @quals[:location].must "Berlin"
    filter = Search::Filters::QueryFilter.new field: :location, qualifiers: @quals

    assert_equal({ bool: { should: [
        { query_string: { query: "Boulder, CO", default_field: :location, default_operator: :AND } },
        { query_string: { query: "San Francisco", default_field: :location, default_operator: :AND } },
        { query_string: { query: "Berlin", default_field: :location, default_operator: :AND } },
    ] } }, filter.must)
  end

  test "changing the default query operator" do
    @quals[:location].must "Boulder, CO"
    filter = Search::Filters::QueryFilter.new field: :location, qualifiers: @quals, default_operator: :OR
    assert_equal({ query_string: { query: "Boulder, CO", default_field: :location, default_operator: :OR } }, filter.must)
  end
end
