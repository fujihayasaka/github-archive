# typed: true
# frozen_string_literal: true

require "test_helper"

class SearchFiltersTermFilterTest < GitHub::TestCase
  setup do
    @quals = Search::ParsedQuery.qualifiers
    @quals[:language].must "Ruby"
    @quals[:label].must "search"
    @quals[:label].must "bug"
    @quals[:empty]  # create an empty BoolCollection
  end

  test "builds a term filter" do
    filter = Search::Filters::TermFilter.new \
      field: :language,
      qualifiers: @quals

    assert_equal({ term: { language: "Ruby" } }, filter.must)
  end

  test "builds a terms filter with execution" do
    filter = Search::Filters::TermFilter.new \
      field: :label,
      qualifiers: @quals,
      execution: :and

    expected = { bool: { must: [
      { term: { label: "search" } },
      { term: { label: "bug" } },
    ] } }
    assert_equal expected, filter.must
  end

  test "empty array" do
    filter = Search::Filters::TermFilter.new \
      field: :empty,
      qualifiers: @quals

    assert_nil filter.must

    filter = Search::Filters::TermFilter.new field: :missing, qualifiers: @quals
    assert_nil filter.must
  end

  test "builds an `exists` filter" do
    quals = Search::ParsedQuery.qualifiers
    quals[:label].must :exists

    filter = Search::Filters::TermFilter.new \
      field: :label,
      qualifiers: quals

    assert_equal({ exists: { field: :label } }, filter.must)
  end

  test "builds a `missing (must-not-exists)` filter" do
    quals = Search::ParsedQuery.qualifiers
    quals[:label].must :missing

    filter = Search::Filters::TermFilter.new \
      field: :label,
      qualifiers: quals

    assert_equal({ bool: { must_not: { exists: { field: :label } } } }, filter.must)
  end
end
