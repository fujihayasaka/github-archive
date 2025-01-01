# typed: true
# frozen_string_literal: true

require "test_helper"

class SearchFiltersMilestoneFilterTest < GitHub::TestCase
  setup do
    @quals = Search::ParsedQuery.qualifiers
  end

  context "exercise std and special ES-bound milestone filters" do

    test "creates a wildcard '*' filter (must exist)" do
      @quals[:milestone].must([Search::Filter::WILDCARD])
      filter = Search::Filters::MilestoneFilter.new qualifiers: @quals

      assert_equal({ exists: { field: :milestone_num } }, filter.must)
      assert filter.must_not.nil?
      assert filter.valid?
    end

    test "creates a wildcard 'any' filter (must exist)" do
      @quals[:milestone].must([Search::Filter::ANY])
      filter = Search::Filters::MilestoneFilter.new qualifiers: @quals

      assert_equal({ exists: { field: :milestone_num } }, filter.must)
      assert filter.must_not.nil?
      assert filter.valid?
    end

    test "creates a 'none' filter (must_not exist)" do
      @quals[:milestone].must([Search::Filter::NONE])
      filter = Search::Filters::MilestoneFilter.new qualifiers: @quals

      assert_equal({ bool: { must_not: { exists: { field: :milestone_num } } } }, filter.must)
      assert filter.must_not.nil?
      assert filter.valid?
    end

    test "creates a 'no' filter (must_not exist)" do
      @quals[:milestone].must([Search::Filter::NO])
      filter = Search::Filters::MilestoneFilter.new qualifiers: @quals

      assert_equal({ bool: { must_not: { exists: { field: :milestone_num } } } }, filter.must)
      assert filter.must_not.nil?
      assert filter.valid?
    end

    test "creates a standard milestone term filter" do
      expected = "goal"
      @quals[:milestone].must([expected])
      filter = Search::Filters::MilestoneFilter.new qualifiers: @quals

      assert_equal({ term: { milestone_title: expected } }, filter.must)
      assert filter.must_not.nil?
      assert filter.valid?
    end

    test "creates a negated milestone term filter" do
      expected = "goal"
      @quals[:milestone].must_not([expected])
      filter = Search::Filters::MilestoneFilter.new qualifiers: @quals

      assert_equal({ bool: { must_not: { term: { milestone_title: expected } } } }, filter.must)
      assert filter.must_not.nil?
      assert filter.valid?
    end

    test "creates a milestone term filter using should" do
      expected = "goal"
      @quals[:milestone].should([expected])
      filter = Search::Filters::MilestoneFilter.new qualifiers: @quals

      assert_equal({ term: { milestone_title: expected } }, filter.should)
      assert filter.must_not.nil?
      assert filter.valid?
    end

    test "creates a milestone terms filter using should" do
      expected = ["first goal", "second goal"]
      @quals[:milestone].should(expected)
      filter = Search::Filters::MilestoneFilter.new qualifiers: @quals

      assert_equal({ terms: { milestone_title: expected } }, filter.should)
      assert filter.must_not.nil?
      assert filter.valid?
    end

    test "doesn't creates a milestone term filter when qualifiers is empty" do
      @quals[:milestone] # create empty bool_collection, all lists nil
      filter = Search::Filters::MilestoneFilter.new qualifiers: @quals

      assert filter.must.nil?
      assert filter.valid?
    end

    test "doesn't creates a milestone term filter when a qualifier value is nil" do
      @quals[:milestone].must = [nil]
      filter = Search::Filters::MilestoneFilter.new qualifiers: @quals

      assert filter.must.nil?
      assert filter.valid?
    end

    test "ensure 'milestone:none' and 'no:milestone' generate equivalent filters" do
      none_quals = @quals.dup
      no_quals   = @quals.dup
      none_quals[:milestone].must([Search::Filter::NO])
      no_quals[:milestone].must([Search::Filter::NONE])
      none_filter = Search::Filters::MilestoneFilter.new qualifiers: none_quals
      no_filter   = Search::Filters::MilestoneFilter.new qualifiers: no_quals

      # All results end up in the "must" branch of the MilestoneFilter
      assert none_filter.must
      assert no_filter.must
      assert_nil none_filter.must_not
      assert_nil no_filter.must_not
    end

    test "ensure 'milestone:any' and 'milestone:*' generate equivalent filters" do
      any_quals = @quals.dup
      wc_quals  = @quals.dup
      any_quals[:milestone].must([Search::Filter::ANY])
      wc_quals[:milestone].must([Search::Filter::WILDCARD])
      any_filter = Search::Filters::MilestoneFilter.new qualifiers: any_quals, keys: @keys
      wc_filter  = Search::Filters::MilestoneFilter.new qualifiers: wc_quals, keys: @keys

      # All results end up in the "must" branch of the MilestoneFilter
      assert any_filter.must
      assert wc_filter.must
      assert any_filter.must_not.nil?
      assert wc_filter.must_not.nil?
      assert_equal(any_filter.must, wc_filter.must)
    end

  end
end
