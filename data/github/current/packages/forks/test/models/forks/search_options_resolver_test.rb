# typed: true
# frozen_string_literal: true

require "test_helper"

class Forks::SearchOptionsResolverTest < GitHub::TestCase
  include Forks::FixtureHelpers

  test "it has the default controls" do
    default = Forks::SearchOptionsResolver.new
    assert_equal 1, default.page
    assert_equal [:active], default.include
    assert_equal :stargazer_counts, default.sort_by
    assert_equal "2y", default.period
  end

  context "it overrides the default controls" do
    test "@page" do
      assert_equal 10, Forks::SearchOptionsResolver.new(page: 10).page
    end

    test "@include" do
      assert_equal [], Forks::SearchOptionsResolver.new(include: []).include
    end

    test "@sort_by" do
      assert_equal :last_updated, Forks::SearchOptionsResolver.new(sort_by: :last_updated).sort_by
    end

    test "@period" do
      assert_equal "1mo", Forks::SearchOptionsResolver.new(period: "1mo").period
    end
  end

  context "it filters invalid values" do
    test "@page" do
      assert_equal 1, Forks::SearchOptionsResolver.new(page: -1).page
      assert_equal 1, Forks::SearchOptionsResolver.new(page: 0).page
      assert_equal 1, Forks::SearchOptionsResolver.new(page: "a").page
      assert_equal 100, Forks::SearchOptionsResolver.new(page: "1000000").page
    end

    test "@include" do
      assert_equal [], Forks::SearchOptionsResolver.new(include: [:invalid]).include
      assert_equal [:archived], Forks::SearchOptionsResolver.new(include: [:archived, :invalid]).include
    end

    test "@sort_by" do
      assert_equal :stargazer_counts, Forks::SearchOptionsResolver.new(sort_by: :invalid).sort_by
    end

    test "@period" do
      assert_equal "2y", Forks::SearchOptionsResolver.new(period: "invalid").period
    end
  end

  context "#copy" do
    test "it copies the state" do
      state = Forks::SearchOptionsResolver.new(include: [:archived, :starred], sort_by: :last_updated)
      assert_equal [:archived, :starred], state.include
      copy = state.copy(include_archived: true, include_inactive: true, include_starred: false)
      assert_equal [:archived, :inactive], copy.include
      assert_equal :last_updated, copy.sort_by
    end
  end

  context "feature management" do
    context "when the state is unfrozen" do
      test "it enables the feature" do
        state = Forks::SearchOptionsResolver.new
        refute state.feature_enabled?(:foo)
        state.enable_search_options_feature(:foo)
        assert state.feature_enabled?(:foo)
      end
    end

    context "when the state is frozen" do
      test "it does not enable the feature" do
        state = Forks::SearchOptionsResolver.new.freeze
        assert_raises RuntimeError do
          state.enable_search_options_feature(:foo)
        end
        refute state.feature_enabled?(:foo)
      end
    end
  end

  context "#persisted" do
    test "it returns true if the state has been persisted" do
      state = Forks::SearchOptionsResolver.new
      refute state.persisted?
      state.persisted = true
      assert state.persisted?
    end

    test "it raises an error if the state is frozen" do
      state = Forks::SearchOptionsResolver.new.freeze
      assert_raises RuntimeError do
        state.persisted = true
      end
      refute_predicate state, :persisted?
    end
  end
end
