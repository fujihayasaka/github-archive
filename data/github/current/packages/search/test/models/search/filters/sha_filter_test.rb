# typed: true
# frozen_string_literal: true

require "test_helper"

class SearchFiltersShaFilterTest < GitHub::TestCase
  setup do
    @quals = Search::ParsedQuery.qualifiers
  end

  test "builds a sha filter" do
    @quals[:sha].must("0123456")

    filter = Search::Filters::ShaFilter.new \
      field: :sha,
      qualifiers: @quals

    assert filter.valid?
  end

  test "rejects invalid values" do
    @quals[:sha].must("012345")

    filter = Search::Filters::ShaFilter.new \
      field: :sha,
      qualifiers: @quals

    refute filter.valid?

    @quals[:sha].must("zzzzzzz")

    filter = Search::Filters::ShaFilter.new \
      field: :sha,
      qualifiers: @quals

    refute filter.valid?
  end
end
