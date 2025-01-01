# typed: true
# frozen_string_literal: true

require "test_helper"

class SearchFiltersPrefixFilterTest < GitHub::TestCase
  setup do
    @quals = Search::ParsedQuery.qualifiers
  end

  test "single prefix filter" do
    @quals[:path].must "vendor/"
    filter = Search::Filters::PrefixFilter.new field: :path, qualifiers: @quals
    assert_equal({ prefix: { path: "vendor/" } }, filter.must)
  end

  test "empty prefix value" do
    @quals[:path].must ""
    filter = Search::Filters::PrefixFilter.new field: :path, qualifiers: @quals
    assert_nil filter.must
  end

  test "array of prefix values" do
    @quals[:path].must "vendor/"
    @quals[:path].must "lib/"
    filter = Search::Filters::PrefixFilter.new field: :path, qualifiers: @quals
    expected = {
      bool: {
        should: [
          { prefix: { path: "vendor/" } },
          { prefix: { path: "lib/" } },
        ],
      },
    }
    assert_equal(expected, filter.must)
  end

  test "empty array" do
    filter = Search::Filters::PrefixFilter.new field: :path, qualifiers: @quals
    assert_nil filter.must
  end
end
