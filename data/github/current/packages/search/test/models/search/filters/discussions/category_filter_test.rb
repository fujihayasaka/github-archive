# typed: true
# frozen_string_literal: true

require "test_helper"

class SearchFiltersDiscussionsCategoryFilterTest < GitHub::TestCase
  fixtures do
    @repo0 = create(:repository)
    @earth0_category = create(:discussion_category, name: "earth🌎", repository: @repo0)
    @wind_category = create(:discussion_category, name: "wind🌬️", repository: @repo0)
    @fire_category = create(:discussion_category, name: "fire🔥", repository: @repo0)

    @repo1 = create(:repository)
    @earth1_category = create(:discussion_category, name: "earth🌎", repository: @repo1)
    @void_category = create(:discussion_category, name: "void", repository: @repo1)
  end

  setup do
    @quals = Search::ParsedQuery.qualifiers
  end

  test "generates an include filter for the correct repository" do
    @quals[:category].must "fire🔥"
    repo = create(:repository)
    fire_category = create(:discussion_category, name: "fire🔥", repository: repo)

    filter = Search::Filters::Discussions::CategoryFilter.new(
      keys: :category,
      qualifiers: @quals,
      repository_ids: [repo.id],
    )

    assert_equal({ term: { category_id: fire_category.id } }, filter.must)
    assert_nil filter.must_not
    assert filter.valid?
  end

  test "removes excluded categories from the include filter" do
    @quals[:category].must %w[earth🌎 wind🌬️ fire🔥]
    @quals[:category].must_not "wind🌬️"

    filter = Search::Filters::Discussions::CategoryFilter.new(
      keys: :category,
      qualifiers: @quals,
      repository_ids: [@repo0.id],
    )

    assert_equal({ terms: { category_id: [@earth0_category.id, @fire_category.id] } }, filter.must)
    assert filter.valid?
  end

  test "generates an exclude filter" do
    @quals[:category].must_not "fire🔥"

    filter = Search::Filters::Discussions::CategoryFilter.new(
      keys: :category,
      qualifiers: @quals,
      repository_ids: [@repo0.id],
    )

    assert_equal({ term: { category_id: @fire_category.id } }, filter.must_not)
    assert filter.valid?
  end

  context "with non-existent categories" do
    test "the filter will be invalid" do
      @quals[:category].must "non-existent-category"

      filter = Search::Filters::Discussions::CategoryFilter.new(
        keys: :category,
        qualifiers: @quals,
        repository_ids: [@repo0.id],
      )

      assert_nil filter.must
      assert !filter.valid?
    end

    context "with valid categories" do
      test "the filter will be valid" do
        @quals[:category].must "wind🌬️"
        @quals[:category].must_not "non-existent-category"

        filter = Search::Filters::Discussions::CategoryFilter.new(
          keys: :category,
          qualifiers: @quals,
          repository_ids: [@repo0.id],
        )

        assert_equal({ term: { category_id: @wind_category.id } }, filter.must)
        assert_nil filter.must_not
        assert !filter.valid?
      end
    end
  end

  context "degenerate inputs" do
    test "creates a valid filter" do
      @quals[:category].must "earth🌎"
      @quals[:category].must_not "earth🌎"

      filter = Search::Filters::Discussions::CategoryFilter.new(
        keys: :category,
        qualifiers: @quals,
        repository_ids: [@repo0.id],
      )

      assert_nil filter.must
      assert_equal({ term: { category_id: @earth0_category.id } }, filter.must_not)
      assert filter.valid?, "filter should be valid"
    end

    test "still creates a valid filter" do
      @quals[:category].must %w[earth🌎 wind🌬️]
      @quals[:category].must_not "wind🌬️"

      filter = Search::Filters::Discussions::CategoryFilter.new(
        keys: :category,
        qualifiers: @quals,
        repository_ids: [@repo0.id],
      )

      assert_equal({ term: { category_id: @earth0_category.id } }, filter.must)
      assert_equal({ term: { category_id: @wind_category.id } }, filter.must_not)
      assert filter.valid?, "filter should be valid"
    end
  end

  context "with multiple repositories" do
    test "locates categories in all" do
      @quals[:category].must %w[wind🌬️ void]

      filter = Search::Filters::Discussions::CategoryFilter.new(
        keys: :category,
        qualifiers: @quals,
        repository_ids: [@repo0.id, @repo1.id],
      )

      assert_equal({ terms: { category_id: [@wind_category.id, @void_category.id] } }, filter.must)
      assert_predicate filter, :valid?
    end

    test "expands categories found in both" do
      @quals[:category].must "earth🌎"

      filter = Search::Filters::Discussions::CategoryFilter.new(
        keys: :category,
        qualifiers: @quals,
        repository_ids: [@repo0.id, @repo1.id],
      )

      assert_equal({ terms: { category_id: [@earth0_category.id, @earth1_category.id] } }, filter.must)
      assert_predicate filter, :valid?
    end

    test "is invalid if categories are found in none" do
      @quals[:category].must %w[NOPE NAH]

      filter = Search::Filters::Discussions::CategoryFilter.new(
        keys: :category,
        qualifiers: @quals,
        repository_ids: [@repo0.id, @repo1.id],
      )

      refute_predicate filter, :valid?
    end
  end
end
