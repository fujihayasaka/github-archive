# typed: true
# frozen_string_literal: true

require "test_helper"

class SearchQueriesSortRuleTest < GitHub::TestCase
  context "#from_hash" do
    test "infers default sort rules" do
      [
        ["asc", { order: "asc", missing: "_last" }],
        [{ order: "desc" }, { order: "desc", missing: "_last" }],
        [{ missing: "_first" }, { order: "asc", missing: "_first" }],
      ].each do |input, expected|
        sort_rule = Search::Queries::SortRule.from_hash({ title: input })
        assert_equal(expected, sort_rule.to_hash[:title])
      end
    end

    test "defaults to 'desc' order when sort field is :_score" do
      sort_rule = Search::Queries::SortRule.from_hash({ _score: { missing: "_last" } })
      assert_equal(
        { _score: { order: "desc", missing: "_last" } },
        sort_rule.to_hash
      )
    end

    test "handles String and Symbol hash keys" do
      string_keys = Search::Queries::SortRule.from_hash(
        { "_score" => { "order" => "asc", "missing" => "_first" } } # non-default values
      )
      assert_equal(
        { _score: { order: "asc", missing: "_first" } },
        string_keys.to_hash
      )
      symbol_keys = Search::Queries::SortRule.from_hash(
        { _score: { order: "asc", missing: "_first" } } # non-default values
      )
      assert_equal(
        { _score: { order: "asc", missing: "_first" } },
        symbol_keys.to_hash
      )
    end
  end

  context "#invert!" do
    test "inverts sort directions" do
      [
        [
          { order: "asc", missing: "_first" },
          { order: "desc", missing: "_last" },
        ],
        [
          { order: "desc", missing: "_last" },
          { order: "asc", missing: "_first" },
        ],
      ].each do |rule, expected_inverted|
        sort_rule = Search::Queries::SortRule.from_hash({ title: rule })
        sort_rule.invert!
        assert_equal(expected_inverted, sort_rule.to_hash[:title])
      end
    end
  end

  context "#to_hash" do
    test "passes through other options" do
      sort_rule = Search::Queries::SortRule.from_hash({ title: { foo: "bar" } })
      assert_equal(
        { title: { order: "asc", missing: "_last", foo: "bar" } },
        sort_rule.to_hash
      )
    end
  end
end
