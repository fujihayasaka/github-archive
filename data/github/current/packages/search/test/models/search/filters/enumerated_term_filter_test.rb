# typed: true
# frozen_string_literal: true

require "test_helper"

class SearchFiltersEnumeratedTermFilterTest < GitHub::TestCase
  setup do
    @quals = Search::ParsedQuery.qualifiers
    @quals[:language].must "Ruby"
    @quals[:label].must "search"
    @quals[:label].must "bug"
    @quals[:empty]  # create an empty BoolCollection
  end

  test "builds a term filter" do
    filter = Search::Filters::EnumeratedTermFilter.new \
      field: :language,
      qualifiers: @quals

    assert_equal({ term: { language: "Ruby" } }, filter.must)
  end

  test "builds a terms filter with execution" do
    filter = Search::Filters::EnumeratedTermFilter.new \
      field: :labels,
      keys: [:label],
      qualifiers: @quals,
      execution: :and

    expected = { bool: { must: [
      { term: { labels: "search" } },
      { term: { labels: "bug" } },
    ] } }
    assert_equal expected, filter.must
  end

  test "turns a single and_should qualifier into a terms query" do
    or_quals = Search::ParsedQuery.qualifiers
    or_quals[:label].and_should(%w[search bug])

    filter = Search::Filters::EnumeratedTermFilter.new \
      field: :labels,
      keys: [:label],
      qualifiers: or_quals,
      execution: :and

    expected = { terms: { labels: %w[search bug] } }
    assert_nil filter.must
    assert_equal expected, filter.should
  end

  test "turns a multiple and_should qualifiers into a 'must' bool query" do
    or_quals = Search::ParsedQuery.qualifiers
    or_quals[:label].and_should(%w[search bug])
    or_quals[:label].and_should(%w[feature enhancement])

    filter = Search::Filters::EnumeratedTermFilter.new \
      field: :labels,
      keys: [:label],
      qualifiers: or_quals,
      execution: :and

    assert_nil filter.should

    expected = { bool: { must: [
                      { bool: { should: { terms: { labels: %w[search bug] } } } },
                      { bool: { should: { terms: { labels: %w[feature enhancement] } } } }] } }
    assert_equal expected, filter.must
  end

  test "turns  multiple and_should qualifiers into a 'must' bool query, combining it with existing 'must' qualifiers" do
    or_quals = Search::ParsedQuery.qualifiers
    or_quals[:label].must(%w[one two])
    or_quals[:label].and_should(%w[search bug])
    or_quals[:label].and_should(%w[feature enhancement])

    filter = Search::Filters::EnumeratedTermFilter.new \
      field: :labels,
      keys: [:label],
      qualifiers: or_quals,
      execution: :and

    assert_nil filter.should

    expected = {
      bool: {
        must: [
          { term: { labels: "one" } },
          { term: { labels: "two" } },
          {
            bool: {
              must: [
                { bool: { should: { terms: { labels: %w[search bug] } } } },
                { bool: { should: { terms: { labels: %w[feature enhancement] } } } }
              ]
            }
          }
        ]
      }
    }
    assert_equal expected, filter.must
  end

  # Behind the scenes the implementation for a single must clause vs multiple ones is different
  test "also combines a single 'must' and 'and_should' correctly" do
    or_quals = Search::ParsedQuery.qualifiers
    or_quals[:label].must(["one"])
    or_quals[:label].and_should(%w[search bug])
    or_quals[:label].and_should(%w[feature enhancement])

    filter = Search::Filters::EnumeratedTermFilter.new \
      field: :labels,
      keys: [:label],
      qualifiers: or_quals,
      execution: :and

    assert_nil filter.should

    expected = {
      bool: {
        must: [
          { term: { labels: "one" } },
          {
            bool: {
              must: [
                { bool: { should: { terms: { labels: %w[search bug] } } } },
                { bool: { should: { terms: { labels: %w[feature enhancement] } } } }
              ]
            }
          }
        ]
      }
    }
    assert_equal expected, filter.must
  end
end
