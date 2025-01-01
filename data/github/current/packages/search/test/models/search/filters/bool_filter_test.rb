# typed: true
# frozen_string_literal: true

require "test_helper"

class SearchFiltersBoolFilterTest < GitHub::TestCase
  fixtures do
    @defunkt = create(:staff_admin_user, login: "defunkt", plan: "medium", email: "chris@ozmm.org")
    @facebox = create(:repository, name: "facebox", owner: @defunkt)
  end

  setup do
    quals = Search::ParsedQuery.qualifiers
    quals[:language].must "Ruby"
    quals[:followers].must ">10"
    quals[:repos].must_not ">100"
    quals[:repo].must "defunkt/facebox"
    builder = Search::FilterBuilder.new quals

    @filters = {}
    @filters[:language]   = builder.language_filter :language, :name
    @filters[:followers]  = builder.range_filter :followers
    @filters[:repos]      = builder.range_filter :repos
    @filters[:repo_id]    = builder.repository_filter @defunkt
  end

  context "when adding filters" do
    test "adds a single filter" do
      bool = Search::Filters::BoolFilter.new
      bool.add_filters @filters[:followers]

      assert_equal 1, bool.filters.length
      assert_same @filters[:followers], bool.filters.first
    end

    test "adds an array of filters" do
      bool = Search::Filters::BoolFilter.new
      bool.add_filters [@filters[:followers], @filters[:repos]]

      assert_equal 2, bool.filters.length
      assert_same @filters[:followers], bool.filters.first
      assert_same @filters[:repos], bool.filters.last
    end

    test "adds filters from a hash" do
      bool = Search::Filters::BoolFilter.new
      bool.add_filters @filters

      assert_equal 4, bool.filters.length
    end

    test "excludes named filters when adding via a hash" do
      bool = Search::Filters::BoolFilter.new(@filters, :repos)
      assert_equal 3, bool.filters.length

      bool = Search::Filters::BoolFilter.new(@filters, [:repos, :repo_id])
      assert_equal 2, bool.filters.length
      assert_same @filters[:language], bool.filters.first
      assert_same @filters[:followers], bool.filters.last
    end
  end

  context "when building" do
    test "creates a single must filter" do
      bool = Search::Filters::BoolFilter.new @filters[:language]
      expected = { bool: { must: { term: { language: "Ruby" } } } }
      assert_equal expected, bool.build
    end

    test "creates a single must_not filter" do
      bool = Search::Filters::BoolFilter.new @filters[:repos]
      expected = { bool: { must_not: { range: { repos: { gt: "100" } } } } }
      assert_equal expected, bool.build
    end

    test "creates an array of filters" do
      bool = Search::Filters::BoolFilter.new @filters, :repos
      expected = { bool: { must: [
        { term: { language: "Ruby" } },
        { range: { followers: { gt: "10" } } },
        { term: { repo_id: @facebox.id } },
      ] } }
      assert_equal expected, bool.build
    end

    test "the whole enchilada" do
      bool = Search::Filters::BoolFilter.new @filters
      expected = { bool: {
        must: [
          { term: { language: "Ruby" } },
          { range: { followers: { gt: "10" } } },
          { term: { repo_id: @facebox.id } },
        ],
        must_not: { range: { repos: { gt: "100" } } },
      } }
      assert_equal expected, bool.build
    end
  end
end
