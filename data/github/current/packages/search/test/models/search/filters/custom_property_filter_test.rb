# typed: true
# frozen_string_literal: true

require "test_helper"

class CustomPropertyFilterTest < GitHub::TestCase
  setup do
    @regex_text = "props\\.\\w+"
    @terms = [@regex_text]
  end

  test "processes conditions from a single term" do
    filter = build_filter("props.secure:true")
    assert_equal %w[secure:true], filter.bool_collection.must
    refute_predicate filter.bool_collection, :must_not?
    assert_nil filter.bool_collection.and_should
  end

  test "processes conditions from a term with comma-syntax" do
    filter = build_filter("props.env:prod,stage")
    refute_predicate filter.bool_collection, :must?
    refute_predicate filter.bool_collection, :must_not?
    assert_equal [%w[env:prod env:stage]], filter.bool_collection.and_should
  end

  test "lowercase values but not property names" do
    filter = build_filter("props.Env:Prod,Stage props.ConsumptionBU:GDD&T")
    assert_equal %w[ConsumptionBU:gdd&t], filter.bool_collection.must
    refute_predicate filter.bool_collection, :must_not?
    assert_equal [%w[Env:prod Env:stage]], filter.bool_collection.and_should
  end

  test "processes conditions from many terms with comma-syntax" do
    filter = build_filter("props.a:1,2,3 props.b:4,5 props.c:6")
    assert_equal %w[c:6], filter.bool_collection.must
    refute_predicate filter.bool_collection, :must_not?
    assert_equal [%w[a:1 a:2 a:3], %w[b:4 b:5]], filter.bool_collection.and_should
  end

  test "processes conditions joining multiple same-key terms" do
    filter = build_filter("props.env:canary props.env:prod,stage props.env:lab")
    assert_equal %w[env:canary env:lab], filter.bool_collection.must
    refute_predicate filter.bool_collection, :must_not?
    assert_equal [%w[env:prod env:stage]], filter.bool_collection.and_should
  end

  context "#build" do
    test "processes conditions joining multiple same-key terms" do
      filter = build_filter("props.env:canary props.env:prod,stage props.env:lab")
      assert_equal %w[env:canary env:lab], filter.bool_collection.must
      refute_predicate filter.bool_collection, :must_not?
      assert_equal [%w[env:prod env:stage]], filter.bool_collection.and_should
    end

    test "combines two values with AND-semantic" do
      filter = build_filter
      expected = [{ term: { sample: "env:none" } }, { term: { sample: "secure:true" } }]

      assert_equal expected, filter.build(["env:none", "secure:true"])
    end
  end

  def build_filter(query_text = "")
    parsed_query = Search::ParsedQuery.new(query_text, @terms, nil, @terms)
    opts = {
      field: :sample,
      key_regex: /#{@regex_text}/,
      qualifiers: parsed_query.qualifiers,
    }
    Search::Filters::CustomPropertyFilter.new(opts)
  end
end
