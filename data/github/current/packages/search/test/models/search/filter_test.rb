# typed: true
# frozen_string_literal: true

require "test_helper"

class SearchFilterTest < GitHub::TestCase
  setup do
    @quals = Search::ParsedQuery.qualifiers
    @quals[:one].must     "one"
    @quals[:two].must     "two"
    @quals[:two].must_not "twenty-two"

    @filter = Search::Filter.new
  end

  test "term filter creation" do
    hash = @filter.build_term_filter(:language, "Ruby")
    assert_equal({ term: { language: "Ruby" } }, hash)
  end

  test "terms filter creation" do
    hash = @filter.build_term_filter(:language, %w[Ruby JavaScript C])
    assert_equal({ terms: { language: %w[Ruby JavaScript C] } }, hash)
  end

  test "terms filter with execution" do
    hash = @filter.build_term_filter(:label, %w[search bug], execution: :and)

    expected = { bool: { must: [
      { term: { label: "search" } },
      { term: { label: "bug" } },
    ] } }
    assert_equal expected, hash
  end

  test "negating a filter" do
    hash = @filter.negate({ term: { language: "Ruby" } })
    assert_equal({ bool: { must_not: { term: { language: "Ruby" } } } }, hash)
  end

  test "filter validity" do
    assert @filter.valid?, "by default filters are valid"
  end

  test "blank filter" do
    assert @filter.blank?, "filters without keys or fields are blank"

    filter = Search::Filter.new field: :one, qualifiers: @quals
    assert !filter.blank?, "filter should not be blank"
  end

  context "with qualifiers but no keys" do
    test "uses the field name as the qualifier key" do
      filter = Search::Filter.new field: :one, qualifiers: @quals

      assert_equal :one, filter.field
      assert_nil filter.keys
      assert_nil filter.must_not
      assert_nil filter.should
      assert_equal({ term: { one: "one" } }, filter.must)
    end
  end

  context "with qualifiers and keys" do
    test "excludes the field name" do
      filter = Search::Filter.new field: :one, keys: :two, qualifiers: @quals

      assert_equal :one, filter.field
      assert_equal [:two], filter.keys
      assert_nil filter.should
      assert_equal({ term: { one: "two" } }, filter.must)
      assert_equal({ term: { one: "twenty-two" } }, filter.must_not)
    end

    test "merges qualifiers together" do
      filter = Search::Filter.new field: :one, keys: [:one, :two], qualifiers: @quals

      assert_equal :one, filter.field
      assert_equal [:one, :two], filter.keys
      assert_nil filter.should
      assert_equal({ terms: { one: %w[one two] } }, filter.must)
      assert_equal({ term: { one: "twenty-two" } }, filter.must_not)
    end
  end

  context "with a transformation block" do
    test "transforms values" do
      filter = Search::Filter.new field: :one, qualifiers: @quals
      filter.map_bool_collection { |value| value.to_s.upcase }

      assert_equal({ term: { one: "ONE" } }, filter.must)
    end

    test 'intersects "must" and "must_not" clasues' do
      @quals[:two].must_not "one"
      filter = Search::Filter.new field: :one, keys: [:one, :two], qualifiers: @quals
      filter.map_bool_collection { |value| value.to_s.upcase }

      assert_equal({ term: { one: "TWO" } }, filter.must)
      assert_equal({ terms: { one: %w[TWENTY-TWO ONE] } }, filter.must_not)
    end
  end
end
