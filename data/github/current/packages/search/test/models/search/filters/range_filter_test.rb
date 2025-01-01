# typed: true
# frozen_string_literal: true

require "test_helper"

class SearchFiltersRangeFilterTest < GitHub::TestCase
  setup do
    @quals = Search::ParsedQuery.qualifiers
    @quals[:language].must "Ruby"
  end

  test "builds a term filter" do
    @quals[:followers].must "42"
    filter = Search::Filters::RangeFilter.new field: :followers, qualifiers: @quals
    assert_equal({ term: { followers: "42" } }, filter.must)
    assert filter.valid?
  end

  test "greater-than filter" do
    @quals[:followers].must ">20"
    filter = Search::Filters::RangeFilter.new field: :followers, qualifiers: @quals
    assert_equal({ range: { followers: { gt: "20" } } }, filter.must)
    assert filter.valid?

    @quals[:followers].clear
    @quals[:followers].must "20..*"
    filter = Search::Filters::RangeFilter.new field: :followers, qualifiers: @quals
    assert_equal({ range: { followers: { gte: "20" } } }, filter.must)
    assert filter.valid?
  end

  test "less-than filter" do
    @quals[:followers].must "<100"
    filter = Search::Filters::RangeFilter.new field: :followers, qualifiers: @quals
    assert_equal({ range: { followers: { lt: "100" } } }, filter.must)
    assert filter.valid?

    @quals[:followers].clear
    @quals[:followers].must "*..100"
    filter = Search::Filters::RangeFilter.new field: :followers, qualifiers: @quals
    assert_equal({ range: { followers: { lte: "100" } } }, filter.must)
    assert filter.valid?
  end

  test "bounded range filter" do
    @quals[:forks].must "10..100"
    filter = Search::Filters::RangeFilter.new field: :forks, qualifiers: @quals
    assert_equal({ range: { forks: { gte: "10", lte: "100" } } }, filter.must)
    assert filter.valid?
  end

  test "unbounded range filter" do
    @quals[:forks].must "* .. *"
    filter = Search::Filters::RangeFilter.new field: :forks, qualifiers: @quals
    assert_nil filter.must
    assert filter.valid?
  end

  test "array of range filters" do
    @quals[:forks].must "* .. 42"
    @quals[:forks].must ">= 69"
    @quals[:forks].must "54"
    filter = Search::Filters::RangeFilter.new field: :forks, qualifiers: @quals

    assert_equal({ bool: { should: [
        { range: { forks: { lte: "42" } } },
        { range: { forks: { gte: "69" } } },
        { term: { forks: "54" } },
    ] } }, filter.must)
    assert filter.valid?
  end

  test "single item array" do
    @quals[:followers].must "< 100"
    filter = Search::Filters::RangeFilter.new field: :followers, qualifiers: @quals
    assert_equal({ range: { followers: { lt: "100" } } }, filter.must)
    assert filter.valid?
  end

  test "missing values" do
    filter = Search::Filters::RangeFilter.new field: :followers, qualifiers: @quals
    assert_nil filter.must
    assert filter.valid?
  end

  test "validates ranges" do
    @quals[:forks].must "10..9"
    filter = Search::Filters::RangeFilter.new field: :forks, qualifiers: @quals

    assert !filter.valid?
    assert_equal "the lower bound of the range (10 .. 9) is greater than the upper bound", filter.invalid_reason

    @quals.clear
    @quals[:forks].must "4.9 .. 4.8"
    filter = Search::Filters::RangeFilter.new field: :forks, qualifiers: @quals

    assert !filter.valid?
    assert_equal "the lower bound of the range (4.9 .. 4.8) is greater than the upper bound", filter.invalid_reason
  end
end
